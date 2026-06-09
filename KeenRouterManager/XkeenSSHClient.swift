import Foundation

private struct SSHConnection: Sendable {
    var host: String
    var port: Int
    var username: String
    var password: String
}

final class XkeenSSHClient: @unchecked Sendable {
    private enum Constants {
        nonisolated static let sshPath = "/usr/bin/ssh"
        nonisolated static let entwarePath = "/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin"
        nonisolated static let shellPath = "/opt/bin/sh"
        nonisolated static let allowedXrayConfigFilenames: Set<String> = [
            "01_log.json",
            "02_dns.json",
            "03_inbounds.json",
            "04_outbounds.json",
            "05_routing.json",
            "06_policy.json"
        ]
    }

    func run(
        _ command: XkeenCommand,
        profile: XkeenSSHProfile,
        input: String? = nil,
        onOutput: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> XkeenCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let shellCommand = try self.makeXkeenShellCommand(command, profile: profile)
            let result = try self.runShellCommand(shellCommand, profile: profile, input: input, onOutput: onOutput)
            return XkeenCommandResult(command: command, exitCode: result.exitCode, output: result.output)
        }.value
    }

    func listBackups(profile: XkeenSSHProfile) async throws -> [XkeenBackupItem] {
        try await Task.detached(priority: .userInitiated) {
            let command = """
            if [ -d /opt/backups ]; then for item in /opt/backups/*; do [ -e "$item" ] || continue; name=${item##*/}; if [ -d "$item" ]; then kind=directory; else kind=file; fi; size=$(du -sk "$item" 2>/dev/null | awk '{print $1}'); modified=$(date -r "$item" '+%Y-%m-%d %H:%M' 2>/dev/null || echo ''); printf '%s\\t%s\\t%s\\t%s\\n' "$name" "$kind" "$size" "$modified"; done; fi
            """
            let result = try self.runShellCommand(command, profile: profile)
            return result.output
                .split(separator: "\n")
                .compactMap { line in
                    let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    guard parts.count >= 4, !parts[0].isEmpty else { return nil }
                    return XkeenBackupItem(
                        name: parts[0],
                        kind: parts[1],
                        sizeKilobytes: Int(parts[2]),
                        modified: parts[3]
                    )
                }
        }.value
    }

    func deleteBackups(_ names: Set<String>, profile: XkeenSSHProfile) async throws -> XkeenCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let safeNames = try names.sorted().map { name in
                guard self.isSafeBackupName(name) else {
                    throw XkeenSSHError.invalidBackupName(name)
                }
                return self.shellQuoted(name)
            }
            let command = "cd /opt/backups && rm -rf -- \(safeNames.joined(separator: " "))"
            let result = try self.runShellCommand(command, profile: profile)
            return XkeenCommandResult(command: .deleteBackups, exitCode: result.exitCode, output: result.output)
        }.value
    }

    func downloadBackups(_ names: Set<String>, to destinationURL: URL, profile: XkeenSSHProfile) async throws -> XkeenCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let safeNames = try names.sorted().map { name in
                guard self.isSafeBackupName(name) else {
                    throw XkeenSSHError.invalidBackupName(name)
                }
                return self.shellQuoted(name)
            }
            let command = "cd /opt/backups && tar -czf - -- \(safeNames.joined(separator: " "))"
            let result = try self.runBinaryDownload(shellCommand: command, profile: profile, destinationURL: destinationURL)
            return XkeenCommandResult(command: .downloadBackups, exitCode: result.exitCode, output: result.output)
        }.value
    }

    func uploadXrayConfigs(_ fileURLs: [URL], profile: XkeenSSHProfile) async throws -> XkeenCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let validatedFileURLs = try self.validatedConfigFileURLs(fileURLs)
            var uploadedFilenames: [String] = []

            for fileURL in validatedFileURLs {
                let filename = fileURL.lastPathComponent
                let command = self.makeConfigUploadCommand(filename: filename)
                _ = try self.runBinaryUpload(shellCommand: command, inputURL: fileURL, profile: profile)
                uploadedFilenames.append(filename)
            }

            return XkeenCommandResult(command: .replaceConfigs, exitCode: 0, output: uploadedFilenames.joined(separator: "\n"))
        }.value
    }

    private nonisolated func makeXkeenShellCommand(_ command: XkeenCommand, profile: XkeenSSHProfile) throws -> String {
        let xkeenPath = profile.xkeenPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !xkeenPath.isEmpty else { throw XkeenSSHError.missingXkeenPath }
        return "PATH=\(Constants.entwarePath) \(shellQuoted(xkeenPath)) \(command.argument)"
    }

    private nonisolated func runShellCommand(
        _ shellCommand: String,
        profile: XkeenSSHProfile,
        input: String? = nil,
        onOutput: @escaping @Sendable (String) -> Void = { _ in }
    ) throws -> (exitCode: Int32, output: String) {
        let connection = try validatedConnection(profile)
        let askPassURL = try makeAskPassHelper()
        defer {
            try? FileManager.default.removeItem(at: askPassURL)
        }

        let process = makeSSHProcess(
            connection: connection,
            shellCommand: shellCommand,
            askPassURL: askPassURL
        )

        let pipe = Pipe()
        let inputPipe = input.map { _ in Pipe() }
        process.standardInput = inputPipe ?? FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = pipe
        process.standardError = pipe
        let output = LockedStringBuffer()
        let interactionDetector = InteractivePromptDetector(isEnabled: input == nil)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            let cleanedChunk = chunk.removingTerminalControlSequences()
            guard !cleanedChunk.isEmpty else { return }
            output.append(cleanedChunk)
            onOutput(cleanedChunk)
            if interactionDetector.shouldTerminate(after: cleanedChunk) {
                process.terminate()
            }
        }

        do {
            try process.run()
            if let input {
                inputPipe?.fileHandleForWriting.write(Data(input.utf8))
                try? inputPipe?.fileHandleForWriting.close()
            }
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw XkeenSSHError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        if interactionDetector.didTerminate {
            throw XkeenSSHError.interactiveInputRequired
        }

        return (process.terminationStatus, output.trimmed())
    }

    private nonisolated func runBinaryDownload(
        shellCommand: String,
        profile: XkeenSSHProfile,
        destinationURL: URL
    ) throws -> (exitCode: Int32, output: String) {
        let connection = try validatedConnection(profile)
        let askPassURL = try makeAskPassHelper()
        defer {
            try? FileManager.default.removeItem(at: askPassURL)
        }

        let temporaryURL = temporaryDownloadURL(for: destinationURL)
        var didMoveDownload = false
        defer {
            if !didMoveDownload {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        if FileManager.default.fileExists(atPath: temporaryURL.path) {
            try FileManager.default.removeItem(at: temporaryURL)
        }
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw XkeenSSHError.downloadFailed("Could not create local archive file.")
        }

        let outputHandle = try FileHandle(forWritingTo: temporaryURL)
        defer {
            try? outputHandle.close()
        }

        let process = makeSSHProcess(
            connection: connection,
            shellCommand: shellCommand,
            askPassURL: askPassURL
        )

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stderr = LockedStringBuffer()
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let archiveWriter = GzipArchiveWriter(outputHandle: outputHandle)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            archiveWriter.write(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            stderr.append(chunk.removingTerminalControlSequences())
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw XkeenSSHError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let message = stderr.trimmed()
        if process.terminationStatus != 0 {
            throw XkeenSSHError.downloadFailed(message.isEmpty ? "tar exited with code \(process.terminationStatus)" : message)
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            didMoveDownload = true
        } catch {
            throw XkeenSSHError.downloadFailed(error.localizedDescription)
        }

        return (process.terminationStatus, destinationURL.path)
    }

    private nonisolated func runBinaryUpload(
        shellCommand: String,
        inputURL: URL,
        profile: XkeenSSHProfile
    ) throws -> (exitCode: Int32, output: String) {
        let connection = try validatedConnection(profile)
        let askPassURL = try makeAskPassHelper()
        defer {
            try? FileManager.default.removeItem(at: askPassURL)
        }

        let inputHandle = try FileHandle(forReadingFrom: inputURL)
        defer {
            try? inputHandle.close()
        }

        let process = makeSSHProcess(
            connection: connection,
            shellCommand: shellCommand,
            askPassURL: askPassURL
        )

        let pipe = Pipe()
        process.standardInput = inputHandle
        process.standardOutput = pipe
        process.standardError = pipe
        let output = LockedStringBuffer()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            let cleanedChunk = chunk.removingTerminalControlSequences()
            guard !cleanedChunk.isEmpty else { return }
            output.append(cleanedChunk)
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw XkeenSSHError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        let message = output.trimmed()
        if process.terminationStatus != 0 {
            throw XkeenSSHError.uploadFailed(message.isEmpty ? "remote command exited with code \(process.terminationStatus)" : message)
        }

        return (process.terminationStatus, message)
    }

    private nonisolated func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private nonisolated func isSafeBackupName(_ name: String) -> Bool {
        !name.isEmpty
            && !name.contains("/")
            && !name.contains("\n")
            && name != "."
            && name != ".."
    }

    private nonisolated func validatedConfigFileURLs(_ fileURLs: [URL]) throws -> [URL] {
        var seenFilenames = Set<String>()
        for fileURL in fileURLs {
            let filename = fileURL.lastPathComponent
            guard isSafeConfigFileName(filename) else {
                throw XkeenSSHError.invalidConfigFileName(filename)
            }
            guard seenFilenames.insert(filename).inserted else {
                throw XkeenSSHError.invalidConfigFileName(filename)
            }
        }

        return fileURLs
    }

    private nonisolated func makeConfigUploadCommand(filename: String) -> String {
        let target = shellQuoted(filename)
        let temporaryFilename = shellQuoted(".\(filename).upload-\(UUID().uuidString)")
        return "cd /opt/etc/xray/configs || exit 1; target=\(target); tmp=\(temporaryFilename); rm -f \"$tmp\"; mode=$(stat -c %a \"$target\" 2>/dev/null || echo 644); if cat > \"$tmp\" && chmod \"$mode\" \"$tmp\" && mv -f \"$tmp\" \"$target\"; then exit 0; else status=$?; rm -f \"$tmp\"; exit \"$status\"; fi"
    }

    private nonisolated func isSafeConfigFileName(_ name: String) -> Bool {
        isSafeBackupName(name)
            && URL(fileURLWithPath: name).pathExtension.lowercased() == "json"
            && Constants.allowedXrayConfigFilenames.contains(name)
    }

    private nonisolated func doubleQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private nonisolated func validatedConnection(_ profile: XkeenSSHProfile) throws -> SSHConnection {
        let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = profile.password.trimmingCharacters(in: .newlines)

        guard !host.isEmpty else { throw XkeenSSHError.missingHost }
        guard !username.isEmpty else { throw XkeenSSHError.missingUsername }
        guard !password.isEmpty else { throw XkeenSSHError.missingPassword }

        return SSHConnection(
            host: host,
            port: profile.port,
            username: username,
            password: password
        )
    }

    private nonisolated func makeSSHProcess(
        connection: SSHConnection,
        shellCommand: String,
        askPassURL: URL
    ) -> Process {
        let remoteCommand = "exec \(Constants.shellPath) -c \(doubleQuoted(shellCommand))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Constants.sshPath)
        process.arguments = [
            "-o", "ConnectTimeout=5",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            "-o", "StrictHostKeyChecking=accept-new",
            "-p", String(connection.port),
            "\(connection.username)@\(connection.host)",
            remoteCommand
        ]
        process.environment = sshEnvironment(password: connection.password, askPassURL: askPassURL)
        return process
    }

    private nonisolated func temporaryDownloadURL(for destinationURL: URL) -> URL {
        destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).download-\(UUID().uuidString)")
    }

    private nonisolated func makeAskPassHelper() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeenRouterManager", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("ssh-askpass-\(UUID().uuidString).sh")
        let script = "#!/bin/sh\nprintf '%s' \"$KRM_SSH_PASSWORD\"\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private nonisolated func sshEnvironment(password: String, askPassURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["DISPLAY"] = environment["DISPLAY"] ?? "localhost:0"
        environment["SSH_ASKPASS"] = askPassURL.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["KRM_SSH_PASSWORD"] = password
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        return environment
    }
}

private final class LockedStringBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var value = ""

    nonisolated init() {}

    nonisolated func append(_ chunk: String) {
        lock.lock()
        value += chunk
        lock.unlock()
    }

    nonisolated func trimmed() -> String {
        lock.lock()
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
        return result
    }
}

private final class InteractivePromptDetector: @unchecked Sendable {
    private let lock = NSLock()
    private let isEnabled: Bool
    private nonisolated(unsafe) var promptCount = 0
    private nonisolated(unsafe) var terminated = false

    nonisolated var didTerminate: Bool {
        lock.lock()
        let result = terminated
        lock.unlock()
        return result
    }

    nonisolated init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    nonisolated func shouldTerminate(after chunk: String) -> Bool {
        guard isEnabled else { return false }

        lock.lock()
        defer { lock.unlock() }

        if chunk.contains("Введите порядковый номер релиза")
            || chunk.contains("Введите порядковый номер")
            || chunk.contains("Ручной ввод версии") {
            promptCount += 1
        }

        if promptCount >= 2 {
            terminated = true
            return true
        }

        return false
    }
}

private final class GzipArchiveWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let outputHandle: FileHandle
    private nonisolated(unsafe) var hasFoundMagic = false
    private nonisolated(unsafe) var pendingByte: UInt8?

    nonisolated init(outputHandle: FileHandle) {
        self.outputHandle = outputHandle
    }

    nonisolated func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        if hasFoundMagic {
            outputHandle.write(data)
            return
        }

        var bytes = [UInt8]()
        if let pendingByte {
            bytes.append(pendingByte)
            self.pendingByte = nil
        }
        bytes.append(contentsOf: data)

        guard !bytes.isEmpty else { return }

        if bytes.count == 1 {
            if bytes[0] == 0x1F {
                pendingByte = bytes[0]
            }
            return
        }

        for index in 0..<(bytes.count - 1) {
            if bytes[index] == 0x1F, bytes[index + 1] == 0x8B {
                hasFoundMagic = true
                outputHandle.write(Data(bytes[index...]))
                return
            }
        }

        if bytes.last == 0x1F {
            pendingByte = bytes.last
        }
    }
}

private extension String {
    nonisolated func removingTerminalControlSequences() -> String {
        var result = String.UnicodeScalarView()
        var state = ParserState.normal

        for scalar in unicodeScalars {
            switch state {
            case .normal:
                if scalar.value == 0x1B {
                    state = .escape
                } else if scalar.value == 0x0D {
                    continue
                } else if scalar.value < 0x20, scalar != "\n", scalar != "\t" {
                    continue
                } else {
                    result.append(scalar)
                }
            case .escape:
                if scalar == "[" {
                    state = .controlSequence
                } else {
                    state = .normal
                }
            case .controlSequence:
                if (0x40...0x7E).contains(scalar.value) {
                    state = .normal
                }
            }
        }

        return String(result)
    }

    private enum ParserState {
        case normal
        case escape
        case controlSequence
    }
}

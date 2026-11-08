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
            let backupPath = self.shellQuoted(AppDefaults.xkeenBackupPath)
            let command = """
            backup_dir=\(backupPath); if [ -d "$backup_dir" ]; then for item in "$backup_dir"/*; do [ -e "$item" ] || continue; name=${item##*/}; if [ -d "$item" ]; then kind=directory; else kind=file; fi; size=$(du -sk "$item" 2>/dev/null | awk '{print $1}'); modified=$(date -r "$item" '+%Y-%m-%d %H:%M' 2>/dev/null || echo ''); printf '%s\\t%s\\t%s\\t%s\\n' "$name" "$kind" "$size" "$modified"; done; fi
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
            let command = "cd \(self.shellQuoted(AppDefaults.xkeenBackupPath)) && rm -rf -- \(safeNames.joined(separator: " "))"
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
            let command = "cd \(self.shellQuoted(AppDefaults.xkeenBackupPath)) && tar -czf - -- \(safeNames.joined(separator: " "))"
            let result = try self.runBinaryDownload(shellCommand: command, profile: profile, destinationURL: destinationURL)
            return XkeenCommandResult(command: .downloadBackups, exitCode: result.exitCode, output: result.output)
        }.value
    }

    func uploadXrayConfigs(_ fileURLs: [URL], profile: XkeenSSHProfile) async throws -> XkeenCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let validatedFileURLs = try self.validatedConfigFileURLs(fileURLs)
            let filenames = validatedFileURLs.map(\.lastPathComponent)
            let archive = try self.makeConfigArchive(from: validatedFileURLs)
            let command = self.makeConfigUploadCommand(filenames: filenames)
            let result = try self.runBinaryUpload(shellCommand: command, input: archive, profile: profile)
            return XkeenCommandResult(command: .replaceConfigs, exitCode: result.exitCode, output: result.output)
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
        input: Data,
        profile: XkeenSSHProfile
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

        let inputPipe = Pipe()
        let pipe = Pipe()
        process.standardInput = inputPipe
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

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: input)
            try inputPipe.fileHandleForWriting.close()
        } catch {
            try? inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            throw XkeenSSHError.uploadFailed(error.localizedDescription)
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
            guard
                let data = try? Data(contentsOf: fileURL),
                let object = try? JSONSerialization.jsonObject(with: data),
                object is [String: Any]
            else {
                throw XkeenSSHError.invalidConfigContents(filename)
            }
        }

        return fileURLs
    }

    private nonisolated func makeConfigArchive(from fileURLs: [URL]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", "-"] + fileURLs.flatMap { fileURL in
            ["-C", fileURL.deletingLastPathComponent().path, fileURL.lastPathComponent]
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw XkeenSSHError.uploadFailed(error.localizedDescription)
        }

        let archive = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                throw XkeenSSHError.uploadFailed(message)
            }
            throw XkeenSSHError.uploadFailed("tar exited with code \(process.terminationStatus)")
        }
        return archive
    }

    private nonisolated func makeConfigUploadCommand(filenames: [String]) -> String {
        let fileList = filenames.map { shellQuoted($0) }.joined(separator: " ")
        let operationID = UUID().uuidString
        let configsDirectory = shellQuoted("/opt/etc/xray/configs")
        let stagingDirectory = shellQuoted("/opt/etc/xray/configs/.krm-upload-\(operationID)")
        let backupDirectory = shellQuoted("\(AppDefaults.xkeenBackupPath)/xray-configs-\(operationID)")

        return """
        configs_dir=\(configsDirectory); staging_dir=\(stagingDirectory); backup_dir=\(backupDirectory); backup_ready=0; completed=0
        cleanup() { rm -rf "$staging_dir"; }
        rollback() { for filename in \(fileList); do if [ -f "$backup_dir/$filename" ]; then cp -p "$backup_dir/$filename" "$configs_dir/$filename"; else rm -f "$configs_dir/$filename"; fi; done; }
        finish() { status=$?; trap - 0; if [ "$backup_ready" -eq 1 ] && [ "$completed" -eq 0 ]; then rollback; fi; cleanup; exit "$status"; }
        trap finish 0; trap 'exit 1' 1 2 15
        [ -d "$configs_dir" ] || exit 1
        mkdir -m 700 "$staging_dir" || exit 1
        tar -xzf - -C "$staging_dir" || exit 1
        for filename in \(fileList); do [ -f "$staging_dir/$filename" ] || exit 1; done
        mkdir -p "$backup_dir" || exit 1
        for filename in \(fileList); do target="$configs_dir/$filename"; if [ -e "$target" ]; then cp -p "$target" "$backup_dir/$filename" || exit 1; fi; done
        backup_ready=1
        for filename in \(fileList); do source="$staging_dir/$filename"; target="$configs_dir/$filename"; mode=$(stat -c %a "$target" 2>/dev/null || echo 644); if ! chmod "$mode" "$source" || ! mv -f "$source" "$target"; then exit 1; fi; done
        completed=1
        printf 'Backup: %s\\n' "$backup_dir"
        for filename in \(fileList); do printf '%s\\n' "$filename"; done
        """
    }

    private nonisolated func isSafeConfigFileName(_ name: String) -> Bool {
        isSafeBackupName(name)
            && URL(fileURLWithPath: name).pathExtension.lowercased() == "json"
            && Constants.allowedXrayConfigFilenames.contains(name)
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
        let remoteCommand = "exec \(Constants.shellPath) -c \(shellQuoted(shellCommand))"
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
        let cleaned = removingANSITerminalSequences(replacingCarriageReturnsWithNewlines: true)
        return cleaned
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !String($0).isDownloadProgressLine }
            .joined(separator: "\n")
    }

    private nonisolated func removingANSITerminalSequences(replacingCarriageReturnsWithNewlines: Bool) -> String {
        var result = String.UnicodeScalarView()
        var state = ParserState.normal

        for scalar in unicodeScalars {
            switch state {
            case .normal:
                if scalar.value == 0x1B {
                    state = .escape
                } else if scalar.value == 0x0D {
                    if replacingCarriageReturnsWithNewlines {
                        result.append("\n")
                    }
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

    private nonisolated var isDownloadProgressLine: Bool {
        let trimmed = trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        var hasProgressCharacter = false
        var hasPercent = false

        for scalar in trimmed.unicodeScalars {
            switch scalar {
            case "#", "=", "-", "O":
                hasProgressCharacter = true
            case "%":
                hasPercent = true
            case "0"..."9", ".", " ":
                continue
            default:
                return false
            }
        }

        return hasProgressCharacter || hasPercent
    }

    private enum ParserState {
        case normal
        case escape
        case controlSequence
    }
}

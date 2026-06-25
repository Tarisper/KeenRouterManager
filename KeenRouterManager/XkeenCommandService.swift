import Foundation

/**
 * Application-level facade for Xkeen SSH operations.
 *
 * The service keeps the low-level SSH client out of `MainViewModel` while
 * preserving the same command surface used by the Xkeen control sheet.
 */
final class XkeenCommandService {
    private let sshClient = XkeenSSHClient()

    func run(
        _ command: XkeenCommand,
        profile: XkeenSSHProfile,
        input: String? = nil,
        onOutput: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> XkeenCommandResult {
        try await sshClient.run(command, profile: profile, input: input, onOutput: onOutput)
    }

    func listBackups(profile: XkeenSSHProfile) async throws -> [XkeenBackupItem] {
        try await sshClient.listBackups(profile: profile)
    }

    func deleteBackups(_ names: Set<String>, profile: XkeenSSHProfile) async throws -> XkeenCommandResult {
        try await sshClient.deleteBackups(names, profile: profile)
    }

    func downloadBackups(
        _ names: Set<String>,
        to destinationURL: URL,
        profile: XkeenSSHProfile
    ) async throws -> XkeenCommandResult {
        try await sshClient.downloadBackups(names, to: destinationURL, profile: profile)
    }

    func uploadXrayConfigs(_ fileURLs: [URL], profile: XkeenSSHProfile) async throws -> XkeenCommandResult {
        try await sshClient.uploadXrayConfigs(fileURLs, profile: profile)
    }
}

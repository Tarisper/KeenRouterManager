import SwiftUI

struct XkeenControlView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    let profile: XkeenSSHProfile
    let runCommand: (XkeenCommand, String?, @escaping @Sendable (String) -> Void) async throws -> XkeenCommandResult
    let listBackups: () async throws -> [XkeenBackupItem]
    let deleteBackups: (Set<String>) async throws -> XkeenCommandResult
    let downloadBackups: (Set<String>, URL) async throws -> XkeenCommandResult
    let uploadConfigs: ([URL]) async throws -> XkeenCommandResult

    @State private var isRunning = false
    @State private var selectedCommand: XkeenCommand?
    @State private var result: XkeenCommandResult?
    @State private var liveOutput = ""
    @State private var errorMessage: String?
    @State private var backups: [XkeenBackupItem] = []
    @State private var selectedBackups: Set<String> = []
    @State private var isLoadingBackups = false
    @State private var isDeleteBackupConfirmationShown = false
    @State private var isXrayReleaseSelectionPresented = false
    @State private var xrayReleaseChoices: [XrayReleaseChoice] = []
    @State private var selectedXrayReleaseNumber: Int?

    private var areActionControlsDisabled: Bool {
        isRunning || isLoadingBackups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(localization.text("xkeen.ssh.target"))
                        .foregroundStyle(.secondary)
                    Text("\(profile.username)@\(profile.host):\(profile.port)")
                }
                GridRow {
                    Text(localization.text("xkeen.path"))
                        .foregroundStyle(.secondary)
                    Text(profile.xkeenPath)
                }
            }
            .font(.callout)

            VStack(alignment: .leading, spacing: 10) {
                commandGroup([
                    .status,
                    .start,
                    .stop,
                    .restart
                ])
                commandGroup([
                    .updateGeo,
                    .updateXray,
                    .updateXkeen
                ])
                commandGroup([
                    .backupXkeen,
                    .backupConfig,
                    .restoreXkeen,
                    .restoreConfig
                ])
                Button {
                    replaceConfigs()
                } label: {
                    Label(localization.text("xkeen.command.replaceConfigs"), systemImage: XkeenCommand.replaceConfigs.systemImage)
                }
                .controlSize(.small)
                .help(localization.text("xkeen.command.replaceConfigs"))
                .disabled(areActionControlsDisabled)
            }

            GroupBox(localization.text("xkeen.output")) {
                ScrollView {
                    Text(outputText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 180)
            }

            backupSection

            HStack {
                Text(localization.text("xkeen.ssh.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(localization.text("action.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
        .task {
            await refreshBackups()
        }
        .confirmationDialog(
            localization.text("xkeen.backups.deleteConfirm.title"),
            isPresented: $isDeleteBackupConfirmationShown
        ) {
            Button(localization.text("xkeen.backups.deleteConfirm.action"), role: .destructive) {
                Task { await deleteSelectedBackups() }
            }
            Button(localization.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(localization.text("xkeen.backups.deleteConfirm.message", args: [selectedBackups.count]))
        }
        .sheet(isPresented: $isXrayReleaseSelectionPresented) {
            XrayReleaseSelectionView(
                choices: xrayReleaseChoices,
                selectedReleaseNumber: Binding(
                    get: { selectedXrayReleaseNumber },
                    set: { selectedXrayReleaseNumber = $0 }
                ),
                install: { choice in
                    isXrayReleaseSelectionPresented = false
                    run(.updateXray, input: "\(choice.number)\n")
                }
            )
            .environmentObject(localization)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.text("xkeen.title"))
                .font(.title3.weight(.semibold))
            Text(localization.text("xkeen.subtitle"))
                .foregroundStyle(.secondary)
        }
    }

    private var outputText: String {
        if let errorMessage {
            return errorMessage
        }

        if isRunning, let selectedCommand {
            let header = localization.text(
                "xkeen.output.running",
                args: [localization.text(selectedCommand.localizationKey)]
            )
            return liveOutput.isEmpty ? header : header + "\n\n" + liveOutput
        }

        guard let result else {
            return localization.text("xkeen.output.placeholder")
        }

        let body = result.output.isEmpty ? localization.text("xkeen.output.empty") : result.output
        return localization.text(
            "xkeen.output.header",
            args: [localization.text(result.command.localizationKey), result.exitCode]
        ) + "\n\n" + body
    }

    private var backupSection: some View {
        GroupBox(localization.text("xkeen.backups")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(localization.text("xkeen.backups.path"))
                        .foregroundStyle(.secondary)
                    Text("/opt/backups")
                    if isLoadingBackups {
                        ProgressView()
                            .controlSize(.small)
                            .help(localization.text("xkeen.backups.loading"))
                    }
                    Spacer()
                    Button {
                        Task { await refreshBackups() }
                    } label: {
                        Label(localization.text("action.refresh"), systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .help(localization.text("action.refresh"))
                    .disabled(areActionControlsDisabled)

                    Button {
                        downloadSelectedBackups()
                    } label: {
                        Label(localization.text("xkeen.backups.downloadSelected"), systemImage: "square.and.arrow.down")
                    }
                    .labelStyle(.iconOnly)
                    .help(localization.text("xkeen.backups.downloadSelected"))
                    .disabled(areActionControlsDisabled || selectedBackups.isEmpty)

                    Button {
                        isDeleteBackupConfirmationShown = true
                    } label: {
                        Label(localization.text("xkeen.backups.deleteSelected"), systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help(localization.text("xkeen.backups.deleteSelected"))
                    .disabled(areActionControlsDisabled || selectedBackups.isEmpty)
                }

                if backups.isEmpty {
                    Text(isLoadingBackups ? localization.text("xkeen.backups.loading") : localization.text("xkeen.backups.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(backups) { backup in
                                backupRow(backup)
                            }
                        }
                    }
                    .frame(maxHeight: 130)
                }
            }
        }
    }

    private func commandGroup(_ commands: [XkeenCommand]) -> some View {
        HStack(spacing: 8) {
            ForEach(commands) { command in
                commandButton(command)
            }
        }
    }

    private func commandButton(_ command: XkeenCommand) -> some View {
        Button {
            if command == .updateXray {
                loadXrayReleases()
            } else {
                run(command)
            }
        } label: {
            Label(localization.text(command.localizationKey), systemImage: command.systemImage)
        }
        .labelStyle(.titleAndIcon)
        .disabled(areActionControlsDisabled)
        .controlSize(.small)
        .help(localization.text(command.localizationKey))
        .overlay(alignment: .trailing) {
            if isRunning && selectedCommand == command {
                ProgressView().controlSize(.small)
                    .offset(x: 18)
            }
        }
    }

    private func backupRow(_ backup: XkeenBackupItem) -> some View {
        Toggle(isOn: backupSelectionBinding(backup.name)) {
            HStack {
                Image(systemName: backup.kind == "directory" ? "folder" : "doc")
                    .foregroundStyle(.secondary)
                Text(backup.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let size = backup.sizeKilobytes {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size) * 1024, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                if !backup.modified.isEmpty {
                    Text(backup.modified)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .toggleStyle(.checkbox)
        .disabled(areActionControlsDisabled)
    }

    private func backupSelectionBinding(_ name: String) -> Binding<Bool> {
        Binding {
            selectedBackups.contains(name)
        } set: { isSelected in
            if isSelected {
                selectedBackups.insert(name)
            } else {
                selectedBackups.remove(name)
            }
        }
    }

    private func downloadSelectedBackups() {
        guard !areActionControlsDisabled else { return }
        guard !selectedBackups.isEmpty,
              let destinationURL = XkeenFilePanels.chooseBackupDownloadURL(localization: localization)
        else {
            return
        }
        isRunning = true
        errorMessage = nil
        liveOutput = ""
        result = nil
        selectedCommand = .downloadBackups

        Task {
            do {
                result = try await downloadBackups(selectedBackups, destinationURL)
            } catch {
                errorMessage = error.localizedDescription
            }

            isRunning = false
            selectedCommand = nil
        }
    }

    private func replaceConfigs() {
        guard !areActionControlsDisabled else { return }
        let configURLs = XkeenFilePanels.chooseXrayConfigURLs(localization: localization)
        guard !configURLs.isEmpty else { return }

        selectedCommand = .replaceConfigs
        isRunning = true
        errorMessage = nil
        liveOutput = ""
        result = nil

        Task {
            do {
                result = try await uploadConfigs(configURLs)
            } catch {
                errorMessage = error.localizedDescription
            }

            isRunning = false
            selectedCommand = nil
        }
    }

    private func loadXrayReleases() {
        guard !areActionControlsDisabled else { return }
        selectedCommand = .updateXray
        isRunning = true
        errorMessage = nil
        liveOutput = localization.text("xkeen.updateXray.loading") + "\n"
        result = nil

        Task {
            do {
                let releaseListResult = try await runCommand(.updateXray, "0\n", makeLiveOutputHandler())
                result = releaseListResult
                let choices = XrayReleaseParser.parseChoices(from: releaseListResult.output)
                if choices.isEmpty {
                    errorMessage = localization.text("xkeen.updateXray.noReleases")
                } else {
                    xrayReleaseChoices = choices
                    selectedXrayReleaseNumber = choices.first?.number
                    isXrayReleaseSelectionPresented = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isRunning = false
            selectedCommand = nil
        }
    }

    private func run(_ command: XkeenCommand, input: String? = nil) {
        guard !areActionControlsDisabled else { return }
        selectedCommand = command
        isRunning = true
        errorMessage = nil
        liveOutput = ""
        result = nil

        Task {
            do {
                if let backupCommand = command.createsBackupBeforeRun {
                    let backupName = localization.text(backupCommand.localizationKey)
                    await MainActor.run {
                        liveOutput += localization.text("xkeen.output.backupBeforeUpdate", args: [backupName]) + "\n"
                    }
                    _ = try await runCommand(backupCommand, nil, makeLiveOutputHandler())
                }
                result = try await runCommand(command, input, makeLiveOutputHandler())
                await refreshBackups()
            } catch {
                errorMessage = error.localizedDescription
            }

            isRunning = false
            selectedCommand = nil
        }
    }

    @MainActor
    private func refreshBackups() async {
        isLoadingBackups = true
        defer { isLoadingBackups = false }

        do {
            backups = try await listBackups()
            selectedBackups = selectedBackups.intersection(Set(backups.map(\.name)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteSelectedBackups() async {
        guard !areActionControlsDisabled, !selectedBackups.isEmpty else { return }
        isRunning = true
        errorMessage = nil
        result = nil

        do {
            result = try await deleteBackups(selectedBackups)
            selectedBackups.removeAll()
            await refreshBackups()
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    private func makeLiveOutputHandler() -> @Sendable (String) -> Void {
        { chunk in
            Task { @MainActor in
                liveOutput += chunk
            }
        }
    }
}

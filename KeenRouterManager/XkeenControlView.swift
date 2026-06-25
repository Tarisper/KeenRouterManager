import SwiftUI

private struct XkeenCommandExecutionState {
    var isRunning = false
    var selectedCommand: XkeenCommand?
    var result: XkeenCommandResult?
    var liveOutput = ""
    var errorMessage: String?
}

private struct XkeenBackupState {
    var items: [XkeenBackupItem] = []
    var selectedNames: Set<String> = []
    var isLoading = false
}

private struct XkeenSheetState {
    var isDeleteBackupConfirmationShown = false
    var isXrayReleaseSelectionPresented = false
    var isGeoAutoUpdateConfigurationPresented = false
    var xrayReleaseChoices: [XrayReleaseChoice] = []
    var selectedXrayReleaseNumber: Int?
}

struct XkeenControlView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    let profile: XkeenSSHProfile
    let runCommand: (XkeenCommand, String?, @escaping @Sendable (String) -> Void) async throws -> XkeenCommandResult
    let listBackups: () async throws -> [XkeenBackupItem]
    let deleteBackups: (Set<String>) async throws -> XkeenCommandResult
    let downloadBackups: (Set<String>, URL) async throws -> XkeenCommandResult
    let uploadConfigs: ([URL]) async throws -> XkeenCommandResult
    @Binding var geoAutoUpdateDay: Int
    @Binding var geoAutoUpdateHour: Int
    @Binding var geoAutoUpdateMinute: Int

    @State private var commandState = XkeenCommandExecutionState()
    @State private var backupState = XkeenBackupState()
    @State private var sheetState = XkeenSheetState()

    private var areActionControlsDisabled: Bool {
        commandState.isRunning || backupState.isLoading
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
                HStack(spacing: 8) {
                    Button {
                        sheetState.isGeoAutoUpdateConfigurationPresented = true
                    } label: {
                        Label(
                            localization.text("xkeen.command.configureGeoAutoUpdate"),
                            systemImage: XkeenCommand.configureGeoAutoUpdate.systemImage
                        )
                    }
                    .controlSize(.small)
                    .help(localization.text("xkeen.command.configureGeoAutoUpdate"))
                    .disabled(areActionControlsDisabled)

                    commandButton(.disableGeoAutoUpdate)
                }
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
            isPresented: $sheetState.isDeleteBackupConfirmationShown
        ) {
            Button(localization.text("xkeen.backups.deleteConfirm.action"), role: .destructive) {
                Task { await deleteSelectedBackups() }
            }
            Button(localization.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(localization.text("xkeen.backups.deleteConfirm.message", args: [backupState.selectedNames.count]))
        }
        .sheet(isPresented: $sheetState.isXrayReleaseSelectionPresented) {
            XrayReleaseSelectionView(
                choices: sheetState.xrayReleaseChoices,
                selectedReleaseNumber: Binding(
                    get: { sheetState.selectedXrayReleaseNumber },
                    set: { sheetState.selectedXrayReleaseNumber = $0 }
                ),
                install: { choice in
                    sheetState.isXrayReleaseSelectionPresented = false
                    run(.updateXray, input: "\(choice.number)\n")
                }
            )
            .environmentObject(localization)
        }
        .sheet(isPresented: $sheetState.isGeoAutoUpdateConfigurationPresented) {
            XkeenGeoAutoUpdateConfigurationView(
                selectedDay: $geoAutoUpdateDay,
                hour: $geoAutoUpdateHour,
                minute: $geoAutoUpdateMinute,
                cancel: {
                    sheetState.isGeoAutoUpdateConfigurationPresented = false
                },
                apply: {
                    sheetState.isGeoAutoUpdateConfigurationPresented = false
                    run(
                        .configureGeoAutoUpdate,
                        input: configureGeoAutoUpdateInput
                    )
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
        if let errorMessage = commandState.errorMessage {
            return errorMessage
        }

        if commandState.isRunning, let selectedCommand = commandState.selectedCommand {
            let header = localization.text(
                "xkeen.output.running",
                args: [localization.text(selectedCommand.localizationKey)]
            )
            return commandState.liveOutput.isEmpty ? header : header + "\n\n" + commandState.liveOutput
        }

        guard let result = commandState.result else {
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
                    Text(AppDefaults.xkeenBackupPath)
                    if backupState.isLoading {
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
                    .disabled(areActionControlsDisabled || backupState.selectedNames.isEmpty)

                    Button {
                        sheetState.isDeleteBackupConfirmationShown = true
                    } label: {
                        Label(localization.text("xkeen.backups.deleteSelected"), systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help(localization.text("xkeen.backups.deleteSelected"))
                    .disabled(areActionControlsDisabled || backupState.selectedNames.isEmpty)
                }

                if backupState.items.isEmpty {
                    Text(backupState.isLoading ? localization.text("xkeen.backups.loading") : localization.text("xkeen.backups.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(backupState.items) { backup in
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
            if commandState.isRunning && commandState.selectedCommand == command {
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
            backupState.selectedNames.contains(name)
        } set: { isSelected in
            if isSelected {
                backupState.selectedNames.insert(name)
            } else {
                backupState.selectedNames.remove(name)
            }
        }
    }

    private func downloadSelectedBackups() {
        guard !areActionControlsDisabled else { return }
        guard !backupState.selectedNames.isEmpty,
              let destinationURL = XkeenFilePanels.chooseBackupDownloadURL(localization: localization)
        else {
            return
        }
        commandState.isRunning = true
        commandState.errorMessage = nil
        commandState.liveOutput = ""
        commandState.result = nil
        commandState.selectedCommand = .downloadBackups

        Task {
            do {
                commandState.result = try await downloadBackups(backupState.selectedNames, destinationURL)
            } catch {
                commandState.errorMessage = error.localizedDescription
            }

            commandState.isRunning = false
            commandState.selectedCommand = nil
        }
    }

    private func replaceConfigs() {
        guard !areActionControlsDisabled else { return }
        let configURLs = XkeenFilePanels.chooseXrayConfigURLs(localization: localization)
        guard !configURLs.isEmpty else { return }

        commandState.selectedCommand = .replaceConfigs
        commandState.isRunning = true
        commandState.errorMessage = nil
        commandState.liveOutput = ""
        commandState.result = nil

        Task {
            do {
                commandState.result = try await uploadConfigs(configURLs)
            } catch {
                commandState.errorMessage = error.localizedDescription
            }

            commandState.isRunning = false
            commandState.selectedCommand = nil
        }
    }

    private func loadXrayReleases() {
        guard !areActionControlsDisabled else { return }
        commandState.selectedCommand = .updateXray
        commandState.isRunning = true
        commandState.errorMessage = nil
        commandState.liveOutput = localization.text("xkeen.updateXray.loading") + "\n"
        commandState.result = nil

        Task {
            do {
                let releaseListResult = try await runCommand(.updateXray, "0\n", makeLiveOutputHandler())
                commandState.result = releaseListResult
                let choices = XrayReleaseParser.parseChoices(from: releaseListResult.output)
                if choices.isEmpty {
                    commandState.errorMessage = localization.text("xkeen.updateXray.noReleases")
                } else {
                    sheetState.xrayReleaseChoices = choices
                    sheetState.selectedXrayReleaseNumber = choices.first?.number
                    sheetState.isXrayReleaseSelectionPresented = true
                }
            } catch {
                commandState.errorMessage = error.localizedDescription
            }

            commandState.isRunning = false
            commandState.selectedCommand = nil
        }
    }

    private func run(_ command: XkeenCommand, input: String? = nil) {
        guard !areActionControlsDisabled else { return }
        commandState.selectedCommand = command
        commandState.isRunning = true
        commandState.errorMessage = nil
        commandState.liveOutput = ""
        commandState.result = nil

        Task {
            do {
                if let backupCommand = command.createsBackupBeforeRun {
                    let backupName = localization.text(backupCommand.localizationKey)
                    await MainActor.run {
                        commandState.liveOutput += localization.text("xkeen.output.backupBeforeUpdate", args: [backupName]) + "\n"
                    }
                    _ = try await runCommand(backupCommand, nil, makeLiveOutputHandler())
                }
                commandState.result = try await runCommand(command, input, makeLiveOutputHandler())
                await refreshBackups()
            } catch {
                commandState.errorMessage = error.localizedDescription
            }

            commandState.isRunning = false
            commandState.selectedCommand = nil
        }
    }

    @MainActor
    private func refreshBackups() async {
        backupState.isLoading = true
        defer { backupState.isLoading = false }

        do {
            backupState.items = try await listBackups()
            backupState.selectedNames = backupState.selectedNames.intersection(Set(backupState.items.map(\.name)))
        } catch {
            commandState.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteSelectedBackups() async {
        guard !areActionControlsDisabled, !backupState.selectedNames.isEmpty else { return }
        commandState.isRunning = true
        commandState.errorMessage = nil
        commandState.result = nil

        do {
            commandState.result = try await deleteBackups(backupState.selectedNames)
            backupState.selectedNames.removeAll()
            await refreshBackups()
        } catch {
            commandState.errorMessage = error.localizedDescription
        }

        commandState.isRunning = false
    }

    private func makeLiveOutputHandler() -> @Sendable (String) -> Void {
        { chunk in
            Task { @MainActor in
                commandState.liveOutput += chunk
            }
        }
    }
}

private struct XkeenGeoAutoUpdateConfigurationView: View {
    @EnvironmentObject private var localization: LocalizationManager

    @Binding var selectedDay: Int
    @Binding var hour: Int
    @Binding var minute: Int

    let cancel: () -> Void
    let apply: () -> Void

    private let days: [GeoAutoUpdateDay] = GeoAutoUpdateDay.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.text("xkeen.geoAutoUpdate.title"))
                    .font(.title3.weight(.semibold))
                Text(localization.text("xkeen.geoAutoUpdate.message"))
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text(localization.text("xkeen.geoAutoUpdate.day"))
                        .foregroundStyle(.secondary)
                    Picker(localization.text("xkeen.geoAutoUpdate.day"), selection: $selectedDay) {
                        ForEach(days, id: \.self) { day in
                            Text(localization.text("xkeen.geoAutoUpdate.day.\(day.rawValue)"))
                                .tag(day.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                GridRow {
                    Text(localization.text("xkeen.geoAutoUpdate.time"))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Stepper(value: $hour, in: 0...23) {
                            Text(localization.text("xkeen.geoAutoUpdate.hour", args: [hour]))
                                .frame(width: 90, alignment: .leading)
                        }
                        Stepper(value: $minute, in: 0...59) {
                            Text(localization.text("xkeen.geoAutoUpdate.minute", args: [minute]))
                                .frame(width: 110, alignment: .leading)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(localization.text("action.cancel")) {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(localization.text("xkeen.geoAutoUpdate.apply")) {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

// MARK: - XkeenControlView helpers

private extension XkeenControlView {
    var configureGeoAutoUpdateInput: String {
        "\(Self.configureGeoAutoUpdateMenuChoice)\n\(geoAutoUpdateDay)\n\(geoAutoUpdateHour)\n\(geoAutoUpdateMinute)\n"
    }

    /// First menu choice in xkeen's interactive prompt to enable/configure geo auto-update.
    private static let configureGeoAutoUpdateMenuChoice = 1
}

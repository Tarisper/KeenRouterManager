//
//  ContentView.swift
//  KeenRouterManager
//
//  Created by Daniyar Hayitov on 10.04.2026.
//

import SwiftUI

/**
 * Layout constants for the main screen.
 */
private enum LayoutMetrics {
    static let sidebarWidth: CGFloat = 300
    static let statusWidth: CGFloat = 24
    static let nameWidth: CGFloat = 222
    static let ipWidth: CGFloat = 90
    static let detailsWidth: CGFloat = 200
    static let policyWidth: CGFloat = 153
}

/**
 * Convenience conversion between persisted sidebar state and split view visibility.
 */
private extension NavigationSplitViewVisibility {
    init(isRouterListVisible: Bool) {
        self = isRouterListVisible ? .all : .detailOnly
    }

    var isRouterListVisible: Bool {
        self != .detailOnly
    }
}

/**
 * Main application screen.
 */
struct ContentView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @StateObject private var viewModel = MainViewModel()
    @State private var editorPayload: RouterEditorPayload?
    @State private var isDeleteConfirmationShown = false
    @State private var columnVisibility: NavigationSplitViewVisibility

    /**
     * Creates the main screen with the last saved sidebar visibility.
     */
    init() {
        let isRouterListVisible = FileAppSettingsStore.loadCurrent().isRouterListVisible
        _columnVisibility = State(initialValue: NavigationSplitViewVisibility(isRouterListVisible: isRouterListVisible))
    }

    /**
     * Safe selection binding for the router list.
     *
     * Ignores `nil` so clicking an empty list area does not clear selection.
     */
    private var profileSelectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedProfileID },
            set: { newValue in
                // Ignore "click on empty space" deselection to keep current router context.
                guard let newValue else { return }
                guard newValue != viewModel.selectedProfileID else { return }
                DispatchQueue.main.async {
                    viewModel.selectedProfileID = newValue
                }
            }
        )
    }

    /**
     * Applies the fixed window layout for the current sidebar state.
     * - Parameter isRouterListVisible: Optional explicit sidebar visibility.
     */
    private func applyWindowLayout(isRouterListVisible: Bool? = nil) {
        let sidebarVisible = isRouterListVisible ?? columnVisibility.isRouterListVisible
        DispatchQueue.main.async {
            WindowLayout.apply(sidebarVisible: sidebarVisible)
        }
    }

    /**
     * Persists and applies window changes when the split view visibility changes.
     * - Parameter newValue: Updated split view visibility.
     */
    private func handleColumnVisibilityChange(_ newValue: NavigationSplitViewVisibility) {
        let isRouterListVisible = newValue.isRouterListVisible
        if viewModel.isRouterListVisible != isRouterListVisible {
            viewModel.isRouterListVisible = isRouterListVisible
        }
        applyWindowLayout(isRouterListVisible: isRouterListVisible)
    }

    /**
     * Restores split view visibility from the persisted view model state.
     * - Parameter isRouterListVisible: Desired sidebar visibility.
     */
    private func restoreColumnVisibility(isRouterListVisible: Bool) {
        let targetVisibility = NavigationSplitViewVisibility(isRouterListVisible: isRouterListVisible)
        guard columnVisibility != targetVisibility else { return }
        columnVisibility = targetVisibility
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 10) {
                List(selection: profileSelectionBinding) {
                    ForEach(viewModel.profiles) { profile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.body)
                            Text(profile.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(profile.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(maxHeight: .infinity)

                HStack {
                    Button {
                        editorPayload = viewModel.makeNewEditorPayload()
                    } label: {
                        Label(localization.text("action.add"), systemImage: "plus")
                    }

                    Button {
                        editorPayload = viewModel.makeEditorPayloadForSelected()
                    } label: {
                        Label(localization.text("action.edit"), systemImage: "pencil")
                    }
                    .disabled(viewModel.selectedProfile == nil)

                    Spacer()

                    Button(role: .destructive) {
                        isDeleteConfirmationShown = true
                    } label: {
                        Label(localization.text("action.delete"), systemImage: "trash")
                    }
                    .disabled(viewModel.selectedProfile == nil)
                }
            }
            .padding(12)
            .navigationSplitViewColumnWidth(
                min: LayoutMetrics.sidebarWidth,
                ideal: LayoutMetrics.sidebarWidth,
                max: LayoutMetrics.sidebarWidth
            )
        } detail: {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.selectedProfile?.name ?? localization.text("router.fallbackName"))
                                .font(.title3)
                        }

                        Spacer()

                        Toggle(localization.text("toggle.my"), isOn: $viewModel.showOnlyMyDevices)
                            .toggleStyle(.checkbox)
                            .font(.callout)
                            .help(localization.text("toggle.my.help"))

                        Button(localization.text("action.connect")) {
                            Task {
                                await viewModel.connectSelectedProfile()
                            }
                        }
                        .disabled(viewModel.selectedProfile == nil || viewModel.isBusy)

                        Button(localization.text("action.refresh")) {
                            Task {
                                await viewModel.refreshClients()
                            }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isBusy)
                    }

                    if let connectedAddress = viewModel.connectedAddress {
                        Text(localization.text("router.connectedVia", args: [connectedAddress]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()

                Group {
                    if viewModel.filteredClients.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 42, weight: .regular))
                                .foregroundStyle(.secondary)

                            Text(
                                viewModel.isMineFilterActiveWithoutMatches
                                    ? localization.text("empty.noMineClients.title")
                                    : localization.text("empty.noClients.title")
                            )
                                .font(.system(size: 48, weight: .bold))

                            Text(
                                viewModel.isMineFilterActiveWithoutMatches
                                    ? localization.text("empty.noMineClients.subtitle")
                                    : localization.text("empty.noClients.subtitle")
                            )
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        List(viewModel.filteredClients) { client in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(client.isOnline ? Color.green : Color.red)
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                    )
                                    .frame(width: LayoutMetrics.statusWidth, alignment: .center)
                                    .help(client.isOnline ? localization.text("client.online") : localization.text("client.offline"))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.name)
                                        .font(.body)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Text(client.mac)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .frame(width: LayoutMetrics.nameWidth, alignment: .leading)

                                Text(client.ip)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: LayoutMetrics.ipWidth, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localization.text("client.segment", args: [viewModel.displaySegmentSummary(for: client)]))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Text(localization.text("client.connection", args: [viewModel.displayConnectionSummary(for: client)]))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: LayoutMetrics.detailsWidth, alignment: .leading)

                                Menu {
                                    Button(localization.text("policy.default")) {
                                        Task {
                                            await viewModel.applyPolicy(nil, to: client)
                                        }
                                    }

                                    Button(localization.text("policy.blocked")) {
                                        Task {
                                            await viewModel.setClientBlocked(client)
                                        }
                                    }

                                    if !viewModel.policies.isEmpty {
                                        Divider()
                                    }

                                    ForEach(viewModel.policies) { policy in
                                        Button(policy.displayName) {
                                            Task {
                                                await viewModel.applyPolicy(policy.id, to: client)
                                            }
                                        }
                                    }
                                } label: {
                                    Text(viewModel.displayPolicyName(for: client))
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.gray.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                .frame(width: LayoutMetrics.policyWidth, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                        }
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(item: $editorPayload) { payload in
            RouterEditorView(
                payload: payload,
                onCancel: {
                    editorPayload = nil
                },
                onSave: { savedPayload in
                    viewModel.saveProfile(savedPayload)
                    editorPayload = nil
                }
            )
        }
        .confirmationDialog(
            localization.text("dialog.deleteRouter.title"),
            isPresented: $isDeleteConfirmationShown,
            titleVisibility: .visible
        ) {
            Button(localization.text("action.delete"), role: .destructive) {
                viewModel.deleteSelectedProfile()
            }
            Button(localization.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(localization.text("dialog.deleteRouter.message"))
        }
        .alert(localization.text("alert.error.title"), isPresented: $viewModel.isErrorPresented) {
            Button(localization.text("action.ok"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? localization.text("alert.unknown"))
        }
        .task {
            viewModel.loadData()
        }
        .onAppear {
            applyWindowLayout()
        }
        .onChange(of: columnVisibility) { _, newValue in
            handleColumnVisibilityChange(newValue)
        }
        .onChange(of: viewModel.isRouterListVisible) { _, newValue in
            restoreColumnVisibility(isRouterListVisible: newValue)
        }
        .onChange(of: localization.language) { _, _ in
            viewModel.relocalizeVisibleTexts()
        }
    }
}

#Preview {
    ContentView()
}

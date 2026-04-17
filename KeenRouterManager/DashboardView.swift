import SwiftUI

/**
 * Sheet with connection and client summary metrics.
 */
struct DashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var viewModel: MainViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localization.text("dashboard.windowTitle"))
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Group {
                if viewModel.isConnected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            connectionSection
                            metricsSection
                            breakdownSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                } else {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            localization.text("dashboard.disconnectedTitle"),
                            systemImage: "rectangle.3.group.bubble.left",
                            description: Text(localization.text("dashboard.disconnectedSubtitle"))
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if viewModel.isConnected {
                    Button(localization.text("action.refresh")) {
                        Task {
                            await viewModel.refreshClients()
                        }
                    }
                    .disabled(viewModel.isBusy)
                }

                Spacer()

                Button(localization.text("action.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 520, idealHeight: 560)
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.text("dashboard.connection"))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text(localization.text("dashboard.router"))
                        .foregroundStyle(.secondary)
                    Text(viewModel.connectedProfile?.name ?? localization.text("router.fallbackName"))
                }

                GridRow {
                    Text(localization.text("dashboard.address"))
                        .foregroundStyle(.secondary)
                    Text(viewModel.connectedAddress ?? localization.text("common.notAvailable"))
                        .textSelection(.enabled)
                }

                GridRow {
                    Text(localization.text("dashboard.lastRefresh"))
                        .foregroundStyle(.secondary)
                    Text(viewModel.lastRefreshDescription)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricsSection: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            DashboardMetricCard(
                title: localization.text("dashboard.metric.savedRouters"),
                value: "\(viewModel.profiles.count)",
                symbolName: "network"
            )
            DashboardMetricCard(
                title: localization.text("dashboard.metric.totalClients"),
                value: "\(viewModel.clients.count)",
                symbolName: "desktopcomputer"
            )
            DashboardMetricCard(
                title: localization.text("dashboard.metric.onlineClients"),
                value: "\(viewModel.onlineClientCount)",
                symbolName: "dot.radiowaves.left.and.right"
            )
            DashboardMetricCard(
                title: localization.text("dashboard.metric.blockedClients"),
                value: "\(viewModel.blockedClientCount)",
                symbolName: "hand.raised"
            )
            DashboardMetricCard(
                title: localization.text("dashboard.metric.myDevices"),
                value: "\(viewModel.myClientCount)",
                symbolName: "laptopcomputer"
            )
            DashboardMetricCard(
                title: localization.text("dashboard.metric.policies"),
                value: "\(viewModel.policies.count)",
                symbolName: "line.3.horizontal.decrease.circle"
            )
        }
    }

    private var breakdownSection: some View {
        HStack(alignment: .top, spacing: 18) {
            DashboardBreakdownList(
                title: localization.text("dashboard.policyBreakdown"),
                items: viewModel.policyBreakdown
            )

            DashboardBreakdownList(
                title: localization.text("dashboard.segmentBreakdown"),
                items: viewModel.segmentBreakdown
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbolName)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        }
    }
}

private struct DashboardBreakdownList: View {
    let title: String
    let items: [MainViewModel.BreakdownItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if items.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack {
                        Text(item.title)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        }
    }
}

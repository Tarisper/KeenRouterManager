import SwiftUI

/**
 * Result severity for a single connection diagnostic attempt.
 */
enum ConnectionDiagnosticOutcome {
    case success
    case failure

    var symbolName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }
}

/**
 * Single endpoint attempt captured during router diagnostics.
 */
struct ConnectionDiagnosticAttempt: Identifiable {
    let id = UUID()
    var endpoint: String
    var outcome: ConnectionDiagnosticOutcome
    var message: String
}

/**
 * Human-readable report produced by the router diagnostics helper.
 */
struct ConnectionDiagnosticReport: Identifiable {
    let id = UUID()
    var requestedAddress: String
    var normalizedAddress: String
    var succeededEndpoint: String?
    var guidance: String
    var attempts: [ConnectionDiagnosticAttempt]
    var completedAt: Date

    /**
     * Whether at least one candidate endpoint successfully authenticated.
     */
    var isSuccessful: Bool {
        succeededEndpoint != nil
    }
}

/**
 * Sheet that runs router connectivity diagnostics and presents a structured report.
 */
struct ConnectionDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    let payload: RouterEditorPayload
    let runDiagnostics: (RouterEditorPayload) async throws -> ConnectionDiagnosticReport

    @State private var report: ConnectionDiagnosticReport?
    @State private var errorMessage: String?
    @State private var isRunning = true

    private var routerDisplayName: String {
        let trimmed = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localization.text("router.fallbackName") : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localization.text("diagnostics.title"))
                .font(.title3.weight(.semibold))

            if isRunning {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView()
                        .controlSize(.large)

                    Text(localization.text("diagnostics.running", args: [routerDisplayName]))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let report {
                Form {
                    Section {
                        LabeledContent(localization.text("diagnostics.router")) {
                            Text(routerDisplayName)
                        }

                        LabeledContent(localization.text("diagnostics.requestedAddress")) {
                            Text(report.requestedAddress)
                                .textSelection(.enabled)
                        }

                        LabeledContent(localization.text("diagnostics.normalizedAddress")) {
                            Text(report.normalizedAddress)
                                .textSelection(.enabled)
                        }

                        if let succeededEndpoint = report.succeededEndpoint {
                            LabeledContent(localization.text("diagnostics.succeededEndpoint")) {
                                Text(succeededEndpoint)
                                    .textSelection(.enabled)
                            }
                        }

                        LabeledContent(localization.text("diagnostics.completedAt")) {
                            Text(DateFormatter.diagnosticsTimestamp.string(from: report.completedAt))
                        }
                    }

                    Section(localization.text("diagnostics.summary")) {
                        Label(
                            report.isSuccessful
                                ? localization.text("diagnostics.summary.success")
                                : localization.text("diagnostics.summary.failure"),
                            systemImage: report.isSuccessful ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(report.isSuccessful ? Color.green : Color.orange)

                        Text(report.guidance)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Section(localization.text("diagnostics.attempts")) {
                        ForEach(report.attempts) { attempt in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: attempt.outcome.symbolName)
                                    .foregroundStyle(attempt.outcome.tint)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(attempt.endpoint)
                                        .font(.body.monospaced())
                                        .textSelection(.enabled)

                                    Text(attempt.message)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .formStyle(.grouped)
            } else if let errorMessage {
                ContentUnavailableView(
                    localization.text("diagnostics.failed"),
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
            }

            HStack {
                Spacer()
                Button(localization.text("action.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 660, minHeight: 520, idealHeight: 560, alignment: .topLeading)
        .task {
            await loadReport()
        }
    }

    private func loadReport() async {
        do {
            report = try await runDiagnostics(payload)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }
}

private extension DateFormatter {
    static let diagnosticsTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

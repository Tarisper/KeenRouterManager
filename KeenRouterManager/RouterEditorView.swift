import SwiftUI

/**
 * Sheet for creating or editing a router profile.
 *
 * The editor uses a compact form layout and can run a connection diagnostic
 * before the user commits the profile to disk.
 */
struct RouterEditorView: View {
    @EnvironmentObject private var localization: LocalizationManager

    private let profileID: UUID?
    private let onCancel: () -> Void
    private let onSave: (RouterEditorPayload) -> Void
    private let onDiagnose: (RouterEditorPayload) async throws -> ConnectionDiagnosticReport

    @State private var name: String
    @State private var address: String
    @State private var username: String
    @State private var password: String
    @State private var isDiagnosticsPresented = false

    /**
     * Creates the router editor.
     * - Parameters:
     *   - payload: Initial form values.
     *   - onCancel: Cancel callback.
     *   - onSave: Save callback.
     *   - onDiagnose: Async diagnostics callback for the current draft.
     */
    init(
        payload: RouterEditorPayload,
        onCancel: @escaping () -> Void,
        onSave: @escaping (RouterEditorPayload) -> Void,
        onDiagnose: @escaping (RouterEditorPayload) async throws -> ConnectionDiagnosticReport
    ) {
        self.profileID = payload.profileID
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDiagnose = onDiagnose
        _name = State(initialValue: payload.name)
        _address = State(initialValue: payload.address)
        _username = State(initialValue: payload.username)
        _password = State(initialValue: payload.password)
    }

    private var draftPayload: RouterEditorPayload {
        RouterEditorPayload(
            profileID: profileID,
            name: name,
            address: address,
            username: username,
            password: password
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(profileID == nil ? localization.text("editor.createTitle") : localization.text("editor.editTitle"))
                .font(.title3.weight(.semibold))

            Form {
                TextField(localization.text("editor.name"), text: $name)
                TextField(localization.text("editor.address"), text: $address)
                    .textContentType(.URL)
                TextField(localization.text("editor.username"), text: $username)
                SecureField(localization.text("editor.password"), text: $password)
            }
            .formStyle(.grouped)

            Text(localization.text("editor.examples"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(localization.text("action.diagnose")) {
                    isDiagnosticsPresented = true
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Spacer()

                Button(localization.text("action.cancel"), role: .cancel) {
                    onCancel()
                }

                Button(localization.text("action.save")) {
                    onSave(draftPayload)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        password.isEmpty
                )
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560)
        .sheet(isPresented: $isDiagnosticsPresented) {
            ConnectionDiagnosticsView(
                payload: draftPayload,
                runDiagnostics: { payload in
                    try await onDiagnose(payload)
                }
            )
            .environmentObject(localization)
        }
    }
}

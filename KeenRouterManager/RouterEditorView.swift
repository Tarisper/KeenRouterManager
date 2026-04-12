import SwiftUI

/**
 * Modal sheet for creating or editing a router profile.
 */
struct RouterEditorView: View {
    @EnvironmentObject private var localization: LocalizationManager
    private let profileID: UUID?
    private let onCancel: () -> Void
    private let onSave: (RouterEditorPayload) -> Void

    @State private var name: String
    @State private var address: String
    @State private var username: String
    @State private var password: String

    /**
     * Creates a router profile editor view.
     * - Parameters:
     *   - payload: Initial form values.
     *   - onCancel: Cancel callback.
     *   - onSave: Save callback.
     */
    init(payload: RouterEditorPayload, onCancel: @escaping () -> Void, onSave: @escaping (RouterEditorPayload) -> Void) {
        self.profileID = payload.profileID
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: payload.name)
        _address = State(initialValue: payload.address)
        _username = State(initialValue: payload.username)
        _password = State(initialValue: payload.password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(profileID == nil ? localization.text("editor.createTitle") : localization.text("editor.editTitle"))
                .font(.headline)

            TextField(localization.text("editor.name"), text: $name)

            TextField(localization.text("editor.address"), text: $address)

            TextField(localization.text("editor.username"), text: $username)

            SecureField(localization.text("editor.password"), text: $password)

            Text(localization.text("editor.examples"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button(localization.text("action.cancel"), role: .cancel) {
                    onCancel()
                }

                Button(localization.text("action.save")) {
                    onSave(
                        RouterEditorPayload(
                            profileID: profileID,
                            name: name,
                            address: address,
                            username: username,
                            password: password
                        )
                    )
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
        .frame(width: 460)
    }
}

import SwiftUI

struct XrayReleaseSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    let choices: [XrayReleaseChoice]
    @Binding var selectedReleaseNumber: Int?
    let install: (XrayReleaseChoice) -> Void

    private var selectedChoice: XrayReleaseChoice? {
        choices.first { $0.number == selectedReleaseNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.text("xkeen.updateXray.selection.title"))
                    .font(.title3.weight(.semibold))
                Text(localization.text("xkeen.updateXray.selection.message"))
                    .foregroundStyle(.secondary)
            }

            List(choices, selection: $selectedReleaseNumber) { choice in
                HStack {
                    Text(choice.version)
                    if choice.number == choices.first?.number {
                        Text(localization.text("xkeen.updateXray.selection.latest"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("#\(choice.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(Optional(choice.number))
            }
            .frame(minHeight: 180)

            HStack {
                Spacer()
                Button(localization.text("xkeen.updateXray.selection.skip")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(localization.text("xkeen.updateXray.selection.install")) {
                    if let selectedChoice {
                        install(selectedChoice)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedChoice == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
    }
}

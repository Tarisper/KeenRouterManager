import SwiftUI

/**
 * About window content with basic app info and a project link.
 */
struct AboutView: View {
    @EnvironmentObject private var localization: LocalizationManager

    private let repositoryURL = URL(string: "https://github.com/Tarisper/KeenRouterManager")!

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "KeenRouterManager"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(appName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(localization.text("about.version", args: [appVersion]))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(localization.text("about.description"))
                    .font(.body)

                Link(destination: repositoryURL) {
                    Label(localization.text("about.projectLink"), systemImage: "link")
                }
                .font(.body)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 210, alignment: .topLeading)
    }
}

#Preview {
    AboutView()
        .environmentObject(LocalizationManager.shared)
}

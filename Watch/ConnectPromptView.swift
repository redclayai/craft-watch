import SwiftUI

struct ConnectPromptView: View {
    /// Read once on appear: if the app cleared its own credentials, say why rather than
    /// looking like a first run.
    @State private var signOutReason = SharedDefaults.lastSignOutReason

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: signOutReason == nil ? "link.badge.plus" : "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(signOutReason == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.orange))

                Text(signOutReason == nil ? "Connect Craft" : "Signed Out")
                    .font(.headline)

                if let signOutReason {
                    Text(signOutReason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("Open Craft Watch on your iPhone and connect again. After that this app works on its own — no phone needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
        }
    }
}

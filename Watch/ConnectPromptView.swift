import SwiftUI

struct ConnectPromptView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)

                Text("Connect Craft")
                    .font(.headline)

                Text("Open Craft Watch on your iPhone and sign in. After that this app works on its own — no phone needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
        }
    }
}

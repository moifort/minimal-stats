import SwiftUI

struct UpdateView: View {
    let version: String
    let changelog: String
    var onInstall: (() -> Void)?
    var onLater: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                Text(markdownAttributed)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Later") {
                    onLater?()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)

                Spacer()

                Button("Install") {
                    onInstall?()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
        }
        .padding(16)
    }

    private var markdownAttributed: AttributedString {
        (try? AttributedString(markdown: changelog, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(changelog)
    }
}

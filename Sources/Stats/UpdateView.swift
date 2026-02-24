import SwiftUI

struct UpdateView: View {
    let version: String
    let changelog: String
    var onInstall: (() -> Void)?
    var onLater: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Text("Update to v\(version)")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                Text(markdownAttributed)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            Divider()

            HStack {
                Button("Later") {
                    onLater?()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Install") {
                    onInstall?()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 400, height: 350)
    }

    private var markdownAttributed: AttributedString {
        (try? AttributedString(markdown: changelog, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(changelog)
    }
}

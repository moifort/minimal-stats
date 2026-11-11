import SwiftUI

struct UpdateView: View {
    let version: String
    let changelog: String
    var onInstall: (() -> Void)?
    var onLater: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(ChangelogBlock.parse(changelog).enumerated()), id: \.offset) { index, block in
                        blockView(block, isFirst: index == 0)
                    }
                }
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

    @ViewBuilder
    private func blockView(_ block: ChangelogBlock, isFirst: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(.system(size: level <= 2 ? 13 : 12, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, isFirst ? 0 : 4)
        case .bullet(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                Text(Self.inline(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .separator:
            Divider()
                .padding(.vertical, 4)
        case .paragraph(let text):
            Text(Self.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Bold, italics, code and links inside a block
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// The block-level Markdown found in release notes: headings, bullet and numbered
/// lists, separators and paragraphs. `AttributedString(markdown:)` only lays out
/// inline syntax in a `Text`, which showed `## v1.12.0` and `---` as typed.
enum ChangelogBlock: Equatable {
    case heading(level: Int, text: String)
    /// `indent` counts nesting levels; `marker` is "•" or the item's number ("2.")
    case bullet(indent: Int, marker: String, text: String)
    case separator
    case paragraph(String)

    static func parse(_ markdown: String) -> [ChangelogBlock] {
        var blocks: [ChangelogBlock] = []
        /// A paragraph or list item still open to continuation lines
        var openText: String?
        /// The list item that openText belongs to; nil for a paragraph
        var openItem: (indent: Int, marker: String)?

        func close() {
            if let text = openText {
                if let item = openItem {
                    blocks.append(.bullet(indent: item.indent, marker: item.marker, text: text))
                } else {
                    blocks.append(.paragraph(text))
                }
            }
            openText = nil
            openItem = nil
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let leadingSpaces = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }

            if trimmed.isEmpty {
                close()
            } else if isSeparator(trimmed) {
                close()
                blocks.append(.separator)
            } else if let (level, text) = heading(trimmed) {
                close()
                blocks.append(.heading(level: level, text: text))
            } else if let (marker, text) = listItem(trimmed) {
                close()
                openItem = (leadingSpaces / 2, marker)
                openText = text
            } else if let text = openText {
                // A wrapped line continues the paragraph or the list item
                openText = text + " " + trimmed
            } else {
                openText = trimmed
            }
        }
        close()
        return blocks
    }

    private static func isSeparator(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        // Closing hashes ("## Title ##") are optional decoration
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (hashes, text.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> (String, String)? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            return ("•", line.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
        let digits = line.prefix { $0.isNumber }
        let afterDigits = line.dropFirst(digits.count)
        if !digits.isEmpty, digits.count <= 3, let delimiter = afterDigits.first, ".)".contains(delimiter),
           afterDigits.dropFirst().first == " " {
            return ("\(digits).", afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

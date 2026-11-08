import Foundation

/// Lossy Markdown → readable plain text for the in-page find view.
///
/// The find pane renders body text into a native `NSTextView` (for the system
/// find bar), which has no Markdown awareness — so we de-markdown here first.
/// Unlike the sidebar snippet's `plainText` (which collapses everything to one
/// line), `readablePlainText` **preserves line and paragraph structure** so the
/// find view stays readable: headings, list items, and blank lines survive;
/// only the syntax markers are peeled. Not a real parse — a preview transform.
enum HelpBodyText {

    /// Strip inline Markdown markers from a single line: rewrite links/images
    /// `[label](url)` → `label`, then drop emphasis/code/strike runs (`*` `` ` `` `~`).
    /// Underscores are left alone (they appear in prose and identifiers).
    nonisolated static func stripInlineMarkers(_ line: String) -> String {
        var text = line
        text = text.replacingOccurrences(
            of: "!?\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "[*`~]", with: "", options: .regularExpression)
        return text
    }

    /// Convert a Markdown document to readable, newline-preserving plain text:
    /// heading hashes, blockquote `>`, and list markers are removed (lists keep
    /// a `•`/number prefix); fenced-code fences are dropped but their contents
    /// kept verbatim; single-line HTML comments (e.g. `<!-- IMG … -->`) are
    /// dropped; blank lines are preserved as paragraph breaks.
    nonisolated static func readablePlainText(from markdown: String) -> String {
        var out: [String] = []
        var inFence = false

        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence {
                out.append(raw) // code stays verbatim, markers and all
                continue
            }
            if trimmed.hasPrefix("<!--") { continue } // drop image/comment placeholders
            if trimmed.isEmpty { out.append(""); continue }

            if trimmed.hasPrefix("#") {
                let text = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                out.append(stripInlineMarkers(text))
                continue
            }
            if trimmed.hasPrefix(">") {
                let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                out.append(stripInlineMarkers(text))
                continue
            }
            if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first == " " {
                let text = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                out.append("•\t" + stripInlineMarkers(text))
                continue
            }
            if let marker = orderedListMarker(in: trimmed) {
                let rest = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                out.append(marker + "\t" + stripInlineMarkers(rest))
                continue
            }
            out.append(stripInlineMarkers(trimmed))
        }

        return out.joined(separator: "\n")
    }

    /// Returns the ordered-list marker (`"1."`) if `line` starts with `digits + "." + space`.
    private nonisolated static func orderedListMarker(in line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let digits = line[line.startIndex..<dot]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.startIndex...dot])
    }
}

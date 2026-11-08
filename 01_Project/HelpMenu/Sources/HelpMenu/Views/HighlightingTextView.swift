import SwiftUI
import AppKit

/// Read-only body pane that renders de-markdowned plain text and highlights
/// every occurrence of the active Help search term, scrolling the first hit
/// into view with a brief find-indicator pulse.
///
/// Shown in place of the MarkdownUI reading view *only while a search is active*
/// (see `HelpDetailView`), so picking a result shows **where** the term is on
/// the page — no find bar, no ⌘F, no second search field. MarkdownUI can't
/// highlight an arbitrary substring, hence this flat-text render path. ⌘F still
/// works (system find bar) for anyone who reaches for it, but isn't required.
struct HighlightingTextView: NSViewRepresentable {
    let text: String
    let query: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 20, height: 20)
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let key = "\(query)\u{0}\(text)"
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key
        applyHighlight(to: textView)
    }

    private func applyHighlight(to textView: NSTextView) {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var firstMatch: NSRange?
        if !trimmed.isEmpty {
            let highlight = NSColor.systemYellow.withAlphaComponent(0.55)
            for range in HelpViewModel.matchRanges(of: trimmed, in: text) {
                let nsRange = NSRange(range, in: text)
                attributed.addAttribute(.backgroundColor, value: highlight, range: nsRange)
                if firstMatch == nil { firstMatch = nsRange }
            }
        }

        textView.textStorage?.setAttributedString(attributed)

        if let firstMatch {
            textView.scrollRangeToVisible(firstMatch)
            textView.showFindIndicator(for: firstMatch) // brief macOS spotlight pulse on the first hit
        } else {
            textView.scroll(.zero)
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var lastKey: String?
    }
}

import Foundation
import Observation
import SwiftUI

/// Drives the help window: holds content, the current selection, and the
/// in-window search query, exposing filtered/derived state for the views.
@Observable
@MainActor
public final class HelpViewModel {
    /// The host-supplied content. Reassign to swap content live.
    public var content: HelpContent

    /// Currently selected topic id (sidebar selection / detail target).
    public var selection: HelpTopic.ID?

    /// Live search query bound to the window's search field.
    public var searchText: String = ""

    public init(content: HelpContent) {
        self.content = content
        self.selection = content.topics.first?.id
    }

    /// Whether the content has no topics at all (drives the empty state).
    public var isEmpty: Bool { content.isEmpty }

    /// Whether a search is currently active.
    public var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Topics matching the current search (title or body, case-insensitive).
    /// Returns all topics when not searching.
    public var filteredTopics: [HelpTopic] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return content.topics }
        return content.topics.filter { topic in
            topic.title.localizedCaseInsensitiveContains(query)
                || topic.markdown.localizedCaseInsensitiveContains(query)
        }
    }

    /// Filtered topics grouped for sidebar display, preserving order.
    public var filteredGroups: [HelpTopicGroup] {
        HelpContent(topics: filteredTopics).groups
    }

    /// True when a search is active but nothing matched (drives "no results").
    public var hasNoSearchResults: Bool {
        isSearching && filteredTopics.isEmpty
    }

    /// Search results enriched for display: each filtered topic with its title
    /// matches highlighted and (when the body matched) a context snippet. Empty
    /// while not searching — the sidebar then renders plain titles. Computed over
    /// the already-filtered topics (a handful), so it's cheap to recompute.
    public var searchHits: [HelpSearchHit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return filteredTopics.map { topic in
            HelpSearchHit(
                topic: topic,
                highlightedTitle: Self.highlighting(query, in: topic.title),
                snippet: Self.snippet(matching: query, in: topic.markdown)
                    .map { Self.highlighting(query, in: $0) }
            )
        }
    }

    /// Look up the search hit for a given topic id (sidebar row rendering).
    public func hit(for id: HelpTopic.ID) -> HelpSearchHit? {
        searchHits.first { $0.topic.id == id }
    }

    /// The topic for the current selection, if any.
    public var selectedTopic: HelpTopic? {
        guard let selection else { return nil }
        return content.topics.first { $0.id == selection }
    }

    /// Keep the selection valid as search narrows results: if the selected
    /// topic falls out of the filtered set, select the first match.
    public func reconcileSelectionWithFilter() {
        let visible = filteredTopics
        guard !visible.isEmpty else { return }
        if let selection, visible.contains(where: { $0.id == selection }) {
            return
        }
        selection = visible.first?.id
    }
}

// MARK: - Search hits & highlighting

/// One search result, ready to render: the matched topic, its title with
/// matched ranges styled, and an optional body snippet (nil when the match was
/// title-only). Built by `HelpViewModel.searchHits` while searching.
public struct HelpSearchHit: Identifiable, Sendable {
    public let topic: HelpTopic
    /// Title with every matched range visually marked.
    public let highlightedTitle: AttributedString
    /// First body-match preview with the query highlighted, or nil if the body
    /// didn't match (a title-only hit shows no snippet line).
    public let snippet: AttributedString?

    public var id: HelpTopic.ID { topic.id }
}

extension HelpViewModel {
    /// Context captured around a body match. The lead is short so the matched
    /// word lands near the start of the (2-line-clipped) preview rather than
    /// being pushed off the end; the trail carries the rest of the sentence.
    nonisolated private static let snippetLead = 20
    nonisolated private static let snippetTrail = 130

    /// All case-insensitive ranges of `query` in `text`, left to right.
    /// Pure and view-free so it unit-tests directly.
    nonisolated static func matchRanges(of query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let found = text.range(of: query, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            ranges.append(found)
            // Advance past the match; guard against an empty match (defensive).
            searchStart = found.upperBound > found.lowerBound
                ? found.upperBound
                : text.index(after: found.lowerBound)
        }
        return ranges
    }

    /// `text` as an `AttributedString` with every match of `query` styled —
    /// a subtle accent background plus bold, so it survives Reduce Transparency,
    /// Increase Contrast, and the selected-row fill (bold is the fallback cue).
    nonisolated static func highlighting(_ query: String, in text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return attributed }
        for range in matchRanges(of: trimmed, in: text) {
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            let aLower = attributed.index(attributed.startIndex, offsetByCharacters: lower)
            let aUpper = attributed.index(attributed.startIndex, offsetByCharacters: upper)
            attributed[aLower..<aUpper].inlinePresentationIntent = .stronglyEmphasized
            attributed[aLower..<aUpper].backgroundColor = Color.accentColor.opacity(0.25)
        }
        return attributed
    }

    /// A short, de-markdowned preview of the first body match of `query`, with
    /// `…` ellipses around truncated context. Returns nil when the body contains
    /// no match (so a title-only hit shows no snippet). View-free / testable.
    nonisolated static func snippet(matching query: String, in markdown: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // De-markdown the whole body first so the window math and the on-screen
        // text are the same string (markers don't bloat or shift the window),
        // then locate the first match in that clean text.
        let plain = plainText(from: markdown)
        guard let match = plain.range(of: trimmed, options: .caseInsensitive) else { return nil }

        let total = plain.count
        let lowerOffset = plain.distance(from: plain.startIndex, to: match.lowerBound)
        let upperOffset = plain.distance(from: plain.startIndex, to: match.upperBound)
        let startOffset = max(0, lowerOffset - snippetLead)
        let endOffset = min(total, upperOffset + snippetTrail)
        let start = plain.index(plain.startIndex, offsetBy: startOffset)
        let end = plain.index(plain.startIndex, offsetBy: endOffset)

        var window = String(plain[start..<end])
        window = window.trimmingCharacters(in: .whitespaces)
        window = stripLeadingMarkers(window)

        let prefix = startOffset > 0 ? "…" : ""
        let suffix = endOffset < total ? "…" : ""
        return prefix + window + suffix
    }

    /// A light, lossy de-markdown for previews (not a real parse): rewrite
    /// links/images `[label](url)` → `label`, drop inline emphasis/code/strike
    /// markers (`*` `` ` `` `~`), and collapse every whitespace run (incl.
    /// newlines) to a single space. Leading block markers are peeled later, once
    /// the window is cut, by `stripLeadingMarkers`.
    nonisolated static func plainText(from markdown: String) -> String {
        var text = HelpBodyText.stripInlineMarkers(markdown)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Strip leading Markdown block markers (`#`, `>`, `-`, `|`) and the spaces
    /// around them from the front of a snippet window.
    nonisolated static func stripLeadingMarkers(_ text: String) -> String {
        let markers: Set<Character> = ["#", ">", "-", "|", " "]
        return String(text.drop { markers.contains($0) })
    }
}

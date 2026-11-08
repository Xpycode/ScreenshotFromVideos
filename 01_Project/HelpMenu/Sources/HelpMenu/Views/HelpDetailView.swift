import SwiftUI
import MarkdownUI

/// Renders a single topic's markdown in a scrollable pane.
///
/// Markdown rendering goes through `MarkdownUI.Markdown` here so the dependency
/// stays behind this one thin view and can be swapped later. When no topic is
/// selected it shows a neutral placeholder.
struct HelpDetailView: View {
    let topic: HelpTopic?
    /// Bundle resource directory used to resolve relative markdown image paths.
    var imageBaseURL: URL? = nil
    /// Active Help search term. When non-empty, the body switches to the flat
    /// highlighting pane (MarkdownUI can't highlight a substring); empty = the
    /// normal formatted reading view.
    var searchQuery: String = ""

    var body: some View {
        if let topic {
            if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                formattedBody(topic)
            } else {
                HighlightingTextView(
                    text: HelpBodyText.readablePlainText(from: topic.markdown),
                    query: searchQuery
                )
                .id(topic.id)
            }
        } else {
            ContentUnavailableView(
                "Select a Topic",
                systemImage: "sidebar.left",
                description: Text("Choose a topic from the sidebar to read it here.")
            )
        }
    }

    /// The normal MarkdownUI reading view (no active search).
    @ViewBuilder
    private func formattedBody(_ topic: HelpTopic) -> some View {
        ScrollView {
            Markdown(topic.markdown)
                .markdownImageProvider(BundleImageProvider(baseURL: imageBaseURL))
                .markdownTextStyle { FontSize(15) }
                .textSelection(.enabled)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Tie the scroll view's identity to the topic so switching articles
        // starts a fresh scroll view at the top, instead of inheriting the
        // previous topic's scroll offset.
        .id(topic.id)
        // Intentionally no .navigationTitle here: on macOS that would
        // override the help window's title with the topic name. The window
        // keeps the host's title (e.g. "MyApp Help").
    }
}

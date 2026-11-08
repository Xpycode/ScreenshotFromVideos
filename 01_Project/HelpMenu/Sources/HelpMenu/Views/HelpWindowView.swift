import SwiftUI

/// Root view of the help window: a `NavigationSplitView` pairing the topics
/// sidebar with the markdown detail pane, plus the in-window search field.
public struct HelpWindowView: View {
    @Bindable private var model: HelpViewModel

    /// Accepts the caller-owned view model so `HelpWindowController` can update
    /// `selection` from outside the view hierarchy (e.g. on re-open).
    public init(model: HelpViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            HelpSidebarView(model: model)
        } detail: {
            // While a search is active, the detail pane shows the flat
            // highlighting view scrolled to the first hit; otherwise MarkdownUI.
            HelpDetailView(
                topic: model.selectedTopic,
                imageBaseURL: model.content.imageBaseURL,
                searchQuery: model.searchText
            )
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search Help")
        .onChange(of: model.searchText) {
            model.reconcileSelectionWithFilter()
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

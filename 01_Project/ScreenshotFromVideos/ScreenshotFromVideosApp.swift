//
//  ScreenshotFromVideosApp.swift
//  ScreenshotFromVideos
//
//  App-shell modifiers per cookbook 00-app-shell.md (MANDATORY): hidden
//  title bar + dark color scheme. `.environment(\.theme, .dark)` is
//  intentionally skipped — Theme is a static enum, not an EnvironmentKey,
//  and views already read `Theme.primaryBackground` etc. directly.
//

import SwiftUI
import AppKit
import AppCitizenshipKit
import HelpMenu

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Pin the whole app dark so the Help window (a standalone NSWindow
        // that otherwise follows the system) matches the main window.
        // Replaced by the Appearance menu when light mode lands.
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI maps "?" + Command to keyEquivalent "/" + Shift, which shows
        // as Command-Shift-/. Patch it back to "?" so the menu reads
        // Command-? and fires on it (same fix as Conjoyn).
        if let helpMenu = NSApp.helpMenu {
            for item in helpMenu.items where item.keyEquivalent == "/" {
                item.keyEquivalent = "?"
                item.keyEquivalentModifierMask = [.command]
            }
        }
    }
}

@main
struct ScreenshotFromVideosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // VM lives at the App level so the Commands block and ContentView share
    // the same instance. Single-window app — no multi-window concerns.
    @State private var vm = ExtractionViewModel()

    // Sparkle updater. @StateObject + the `UpdaterCommands` struct below (not an
    // inline closure) so "Check for Updates…" re-evaluates its disabled state
    // when `canCheckForUpdates` changes — the closure form lets it go stale.
    @StateObject private var updateController = UpdateController()

    /// App citizenship via AppCitizenshipKit (same wiring as Conjoyn):
    /// Help › Send Feedback… (FeedbackKit → shared `feedback-submit.php`, which
    /// gates on its `ALLOWED_APPS` list), Help › Leave a Tip (tip-jar hub,
    /// `?app=stillsfromvideo`), and a link-rich About panel replacing the
    /// default one. `appID` is the single slug for both feedback and tips.
    private let citizenship = CitizenshipConfig(
        appID: "stillsfromvideo",
        appName: "Stills From Video",
        accent: Theme.accent,
        websiteURL: URL(string: "https://apps.lucesumbrarum.com/stillsfromvideo"),
        privacyURL: URL(string: "https://apps.lucesumbrarum.com/privacy")
    )

    /// Help content: `Help/help-manifest.json` + `help-*.md`, bundled flat into
    /// Resources. A missing manifest falls back to an empty window, never a crash.
    private let helpContent: HelpContent = (try? HelpContent(manifest: "help-manifest", in: .main))
        ?? HelpContent(topics: [], windowTitle: "Stills From Video Help")

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 620)
        .commands {
            // Help › Stills From Video Help (Command-?).
            HelpMenuCommands(content: helpContent, appName: "Stills From Video")
            // Separator between the Help item and "Send Feedback…" — its own
            // after-.help group, declared between the two packages' groups
            // (same-anchor groups order by declaration; cookbook #104).
            CommandGroup(after: .help) { Divider() }
            // One line for Send Feedback… + Leave a Tip + the link-rich About.
            CitizenshipCommands(citizenship)
            UpdaterCommands(updater: updateController)

            // Replace the default (non-functional) "New" item with Open
            // Video. Output-folder picking is exposed via the right-pane
            // button only — adding a menu item for it would be redundant
            // since users set the output folder once per session.
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") {
                    if let url = FilePickers.pickVideos().first {
                        Task { await vm.load(url) }
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            ZoomCommands()
        }
    }
}

/// "Check for Updates…" in the app menu, just under About — matches the
/// sibling published apps. A `Commands` struct with `@ObservedObject` so the
/// disabled state refreshes while Sparkle starts up or a check is in flight.
struct UpdaterCommands: Commands {
    @ObservedObject var updater: UpdateController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

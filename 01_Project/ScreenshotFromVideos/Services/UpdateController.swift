//
//  UpdateController.swift
//  ScreenshotFromVideos
//
//  Sparkle auto-update wrapper, lifted verbatim from the sibling published
//  apps (CropBatch et al.). Configuration lives in Info.plist (SUFeedURL +
//  SUPublicEDKey + SUEnableAutomaticChecks), generated from project.yml's
//  info.properties block — see that file for the appcast/signing setup.
//
//  `import Combine` is explicit here (the siblings get it transitively) so
//  `publisher(for:)` / `.assign(to:)` resolve cleanly under
//  SWIFT_STRICT_CONCURRENCY=complete.
//

import Foundation
import Combine
import Sparkle

/// Controller that manages app updates via the Sparkle framework.
/// Exposes observable state for SwiftUI integration.
@MainActor
final class UpdateController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    /// Whether the updater is currently able to check for updates.
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true → begins checking per Info.plist settings.
        // nil delegates → Sparkle's default behavior + standard update UI.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// The underlying Sparkle updater, for direct property access.
    var updater: SPUUpdater {
        updaterController.updater
    }

    /// Triggers a manual "Check for Updates…" flow.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

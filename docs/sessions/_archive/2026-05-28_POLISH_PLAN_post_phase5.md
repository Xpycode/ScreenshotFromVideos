# Polish Plan — Post-Phase 5 Items 1–3

Three independent polish items, surfaced during the Phase 5 Wave 6 close-out matrix on 2026-05-28. Independent → can ship one at a time in any order. Recommended order at the bottom.

All file paths are absolute. Line numbers reflect HEAD as of 2026-05-28.

---

## Key research finding: WebP cannot be written via ImageIO on macOS

This drove the format choice in Item 2. Triangulated from Apple docs, release notes, a runtime probe, and a sibling-app teardown:

- `CGImageDestinationCopyTypeIdentifiers()` on this Mac (macOS 15+) returns 22 writable types. `org.webmproject.webp` is **not** in the list. Confirmed identifiers for `.png` / `.jpeg` / `.heic` / `.tiff` are writable.
- The Apple WebP collection (`developer.apple.com/documentation/imageio/webp-data`) exposes only *read* metadata keys (`kCGImagePropertyWebP*`).
- Apple Developer Forum #688001 reports `CGImageDestinationCreateWithURL(..., UTType.webP.identifier, …, nil)` returns nil on macOS 11 → 15. No Apple resolution. No mention of a WebP encoder in macOS 14 / 15 / 26 release notes.
- **CropBatch's WebP path is silently broken.** Its `ImageCropService.encode()` (line 784) and `save()` (line 743) call ImageIO directly, no vendored encoder, no SPM dep for libwebp, no fallback. The error is logged at `CropBatchApp.swift:368` and execution continues; no file is written. The README's "PNG, JPEG, HEIC, TIFF, WebP" claim is inaccurate. We do **not** want to ship the same bug.

**Decision: SFV will ship PNG / JPG / HEIC.** No WebP. If WebP becomes non-negotiable later, vendor [SDWebImageWebPCoder](https://github.com/SDWebImage/SDWebImageWebPCoder) (~200 KB libwebp), accept the notarization/hardened-runtime cost, and route only `.webp` through it while keeping ImageIO for the other three. Deferred until/unless requested.

---

## Item 1 — Frame-count preview in right pane

**Goal:** Surface "N frames will be exported" near the Export button so the user knows the magnitude before clicking. Cheap to compute; clarity win.

**Effort:** ~30 LOC across 3 files. One session.

### Files

| File | Change |
|---|---|
| `Core/TimeListGenerator.swift` (lines 12–45) | Add `static func count(for:duration:fps:) -> Int` — pure arithmetic for interval modes, delegates to `times(…).count` for manual mode (small N). |
| `App/ExtractionViewModel.swift` (lines 36–81 properties; 224–250 buildRequest) | Add `var currentMode: ExtractionMode?` computed (factor the mode-resolution out of `buildRequest`). Add `var previewFrameCount: Int` reading metadata + currentMode. |
| `UI/RightPaneView.swift` (line 260 inside `exportFooter` VStack) | New `Text` row at the top: `"\(n) frame\(n == 1 ? "" : "s") will be exported"`. Hidden when no source loaded or while running (existing progress already covers that state). |

### Implementation sketch

```swift
// TimeListGenerator.swift — add at end of enum
static func count(for mode: ExtractionMode, duration: Double, fps: Float = 30) -> Int {
    guard duration > 0 else { return 0 }
    switch mode {
    case .interval(let seconds):
        guard seconds > 0 else { return 0 }
        return Int((duration / seconds).rounded(.down)) + 1
    case .intervalFrames(let count):
        guard count > 0, fps > 0 else { return 0 }
        let step = Double(count) / Double(fps)
        return Int((duration / step).rounded(.down)) + 1
    case .timestamps:
        return times(for: mode, duration: duration, fps: fps).count
    }
}
```

```swift
// ExtractionViewModel.swift — new computed properties
var currentMode: ExtractionMode? {
    switch tab {
    case .interval:
        switch intervalUnit {
        case .seconds: return intervalSeconds > 0 ? .interval(seconds: intervalSeconds) : nil
        case .frames:  return intervalFrames > 0 ? .intervalFrames(count: intervalFrames) : nil
        }
    case .manual:
        return manualTimes.isEmpty ? nil : .timestamps(manualTimes)
    }
}

var previewFrameCount: Int {
    guard let metadata, let mode = currentMode else { return 0 }
    return TimeListGenerator.count(for: mode, duration: metadata.duration, fps: metadata.nominalFrameRate)
}
```

`buildRequest()` collapses to `guard let sourceURL, let outputFolder, let mode = currentMode else { return nil }` — fewer lines, same behavior.

```swift
// RightPaneView.swift — first child of exportFooter VStack
if vm.metadata != nil && !vm.isRunning {
    let n = vm.previewFrameCount
    Text("\(n) frame\(n == 1 ? "" : "s") will be exported")
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
}
```

### Decisions
- **Pluralization:** Native `n == 1` ternary. Avoid `String.localizedStringWithFormat` — the app is English-only.
- **Zero frames:** shown as "0 frames will be exported" (informative — tells the user manual mode is empty). Alternative: hide row when 0; rejected because then user wonders why the Export button is disabled.
- **Cost:** `previewFrameCount` recomputes on every SwiftUI body call. For interval modes it's two divs and an Int conversion; for manual it allocates an `[CMTime]` of size `manualTimes.count` (dozens, max). Effectively free.

### Open question
- Wording: `"N frames will be exported"` vs `"N frames"` vs `"Export: N frames"`. Picked the verbose form for clarity; if too noisy, drop to `"N frames"`.

---

## Item 2 — Multi-format export (PNG / JPG / HEIC) + quality slider

**Goal:** PNG (current) plus JPG and HEIC alternatives. Quality slider visible only for lossy formats. Persisted across sessions.

**Effort:** ~120 LOC across 7 files. 1–2 sessions.

### Files

| File | Change |
|---|---|
| **NEW** `Models/ExportFormat.swift` (~35 LOC) | Lift CropBatch's enum (with TIFF and WebP dropped). |
| `Services/ImageExportService.swift` (lines 54–67) | Rename `writePNG` → `writeImage(_:to:format:quality:)`. Switch UTType, conditionally add `kCGImageDestinationLossyCompressionQuality` for `supportsCompression`. |
| `Models/ExtractionRequest.swift` (lines 12–18) | Add `var format: ExportFormat = .png` and `var quality: Double = 0.85`. |
| `App/Preferences.swift` (entire file ~131 LOC) | Add `exportFormat` (UserDefaults key `exportFormat`, default `"PNG"`) and `exportQuality` (key `exportQuality`, default `0.85`). Mirrors existing static read/write pattern. |
| `App/ExtractionViewModel.swift` (lines 36–81 properties; init; buildRequest) | Add `@Observable var exportFormat: ExportFormat` and `var exportQuality: Double` (no default; populated in init from `Preferences`, write-through via `didSet`). Pass into `buildRequest()`. |
| `Core/ExtractionPipeline.swift` (lines 93–106) | Change the `writePNG` call to `writeImage(final, to: url, format: request.format, quality: request.quality)`. Change the URL builder's `ext:` argument from `"png"` to `request.format.fileExtension`. |
| `UI/RightPaneView.swift` (new section above `exportFooter`) | Format picker (3 small bordered buttons, matching CropBatch's pattern) + conditional QualitySlider when `vm.exportFormat.supportsCompression`. |

### ExportFormat enum (lifted from CropBatch, simplified)

```swift
// Models/ExportFormat.swift
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case png  = "PNG"
    case jpeg = "JPG"
    case heic = "HEIC"

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .png:  return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }

    /// Hardcoded — `UTType.jpeg.preferredFilenameExtension` returns "jpeg"; we want "jpg".
    var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        }
    }

    var supportsCompression: Bool {
        switch self {
        case .jpeg, .heic: return true
        case .png:         return false
        }
    }
}
```

### ImageExportService rewrite

```swift
// Services/ImageExportService.swift
static func writeImage(_ cgImage: CGImage, to url: URL, format: ExportFormat, quality: Double) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, format.utType.identifier as CFString, 1, nil
    ) else { throw ImageExportError.failedToCreateDestination }

    var options: [CFString: Any] = [:]
    if format.supportsCompression {
        options[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, quality))
    }
    CGImageDestinationAddImage(destination, cgImage, options.isEmpty ? nil : options as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
        throw ImageExportError.failedToWriteImage
    }
}
```

Old `writePNG(_:to:)` can stay as a thin wrapper (`writeImage(image, to: url, format: .png, quality: 1.0)`) if any other caller needs it, but a grep should show only `ExtractionPipeline.swift:97` uses it — safe to delete.

### RightPaneView additions

New section just above `exportFooter` (or as a disclosure group inside the existing settings stack — pick during implementation):

```swift
private var formatSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        LabeledContent("Format") {
            HStack(spacing: 4) {
                ForEach(ExportFormat.allCases) { fmt in
                    Button(fmt.rawValue) { vm.exportFormat = fmt }
                        .buttonStyle(.bordered)
                        .tint(vm.exportFormat == fmt ? .accentColor : .secondary)
                }
            }
            .controlSize(.small)
        }
        if vm.exportFormat.supportsCompression {
            HStack {
                Text("Quality")
                    .font(.callout)
                Slider(value: $vm.exportQuality, in: 0.1...1.0, step: 0.05)
                    .controlSize(.small)
                Text("\(Int(vm.exportQuality * 100))%")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}
```

### Decisions
- **No WebP** (see top of doc).
- **Default format:** PNG (preserves current behavior; first-run users get exactly today's output).
- **Default quality:** 0.85 — JPEG-typical "visually lossless". HEIC at 0.85 produces files larger than necessary; **alternative is to store per-format quality** (`{ jpeg: 0.85, heic: 0.75 }`). Recommendation: single shared `exportQuality` for now (simpler UI, simpler Preferences). Revisit only if user complains HEIC files are too big.
- **Quality slider range:** 0.1–1.0, step 0.05 (CropBatch's exact spec).
- **Quality slider visibility:** hidden, not disabled, when PNG selected. Matches CropBatch.
- **No menu items** for format / quality. Right-pane controls only. (Optional `@FocusedValue`-based `View > Format` menu could come later; not in scope.)
- **No file-extension migration** for existing exports. New format affects new exports only; collision logic (`_1`, `_2`) is per-extension so a `.jpg` next to `frame.png` won't trigger.
- **Lossless quality:** when PNG is selected, `quality` is ignored (PNG is always lossless). `ExtractionRequest.quality` carries the value through anyway; `writeImage` ignores it when `!format.supportsCompression`.

### Open questions
- **JPEG + alpha:** SFV's frames have no alpha (AVFoundation strips it). Confirm by running an overlay-on export to JPG and checking visually that timestamps render correctly. Per ImageIO docs, alpha is silently dropped to opaque black — fine for our case since the source has no alpha.
- **Color profile:** AVFoundation hands back sRGB or Display P3 CGImages. ImageIO preserves the source colorspace. No work needed unless we see color shifts on JPG; if so, add `kCGImageDestinationOptimizeColorForSharing`.

### Out of scope for this item
- TIFF (would be 4 LOC if added — easy to revisit).
- Lossless HEIC (HEIC supports lossless mode but ImageIO's `quality=1.0` doesn't reliably trigger it; if needed, would require explicit `kCGImageDestinationLossyCompressionQuality` omission — minor).
- Format choice per-extraction-mode (e.g., "Interval uses HEIC, Manual uses PNG"). One global format suffices.

---

## Item 3 — Unload-video control clarity

**Goal:** The current ✕ icon at `LeftPaneView.swift:127–137` reads as ambiguous (close cell? remove timestamp?). Replace with a labeled affordance.

**Effort:** ~10 LOC, one file. 10 minutes.

### File

| File | Change |
|---|---|
| `UI/LeftPaneView.swift` (lines 127–158, footer) | Replace `Image(systemName: "xmark.circle.fill")` with `Label("Unload", systemImage: "xmark.circle.fill")`. Improve tooltip. |

### Implementation sketch

```swift
// Was:
//   Image(systemName: "xmark.circle.fill")
//       .font(.system(size: 14))
//       .foregroundStyle(Theme.secondaryText)
//   .help("Remove video")

Button {
    vm.clear()
} label: {
    Label("Unload", systemImage: "xmark.circle.fill")
        .labelStyle(.titleAndIcon)
        .font(.system(size: 13))
        .foregroundStyle(Theme.secondaryText)
}
.buttonStyle(.plain)
.help("Remove this video from the app. The source file is not deleted.")
```

### Decisions
- **Label text:** "Unload" beats "Close Video" (no ambiguity with closing the window) and beats "Remove" (sounds destructive to the source file). "Unload" is the standard term in media tools.
- **Icon kept:** `xmark.circle.fill` stays for visual continuity with the prior state. Alternative `eject.circle` was considered — eject is a stronger metaphor but less common; not worth the swap.
- **Tooltip:** clarifies the source file isn't deleted, addressing the "is this destructive?" worry.
- **No menu item.** A File > Close Video / Unload Video menu item was considered; rejected because it would either need a non-standard shortcut (⌘W belongs to window close) or no shortcut (then the menu is pure clutter). The footer button is discoverable enough once labeled.

### Out of scope
- Confirmation dialog. Unloading is non-destructive (manualTimes are transient by design — see Preferences pattern); a dialog would be friction without value.

---

## Recommended ship order

1. **Item 3 first** (10 min) — smallest, frees up the matrix gripe from the close-out session, ships independently.
2. **Item 1 next** (one session) — useful on its own AND directly improves Item 2's UX by showing the count for any format choice. The `previewFrameCount` plumbing also gives us a counter we can show in the Format section if we ever want a "≈ X MB" estimate later.
3. **Item 2 last** (1–2 sessions) — the bigger lift; benefits from Item 1's count display already being live.

Each ships green build → user smoke → commit. No interdependencies that would force bundling.

---

## Cross-cutting notes

- **xcodegen:** the new `Models/ExportFormat.swift` lives under `01_Project/ScreenshotFromVideos/Models/`. The sources glob (`project.yml:26-28`) auto-discovers — no `xcodegen generate` needed unless build settings change.
- **Strict concurrency:** all touched code is already MainActor-bound (`ExtractionViewModel` is `@Observable @MainActor`; `ImageExportService` static funcs are non-isolated and safe per ImageIO's thread guidance — confirmed in research).
- **Preferences pattern:** Item 2's new keys follow the existing `nonisolated(unsafe) static let defaults` pattern; no Swift 6 friction expected.
- **No new dependencies.** All three items use only existing frameworks (`UniformTypeIdentifiers`, `ImageIO`, SwiftUI).

---

## Promotion to `docs/decisions.md` after ship

Once each item ships, promote its decisions to the long-form log:
- Item 1: pluralization choice; placement above progress; computed-property pattern.
- Item 2: **WebP omission rationale** (this is the load-bearing decision — future-me will thank present-me for the documented reasoning); single shared quality vs per-format; default 0.85; format-picker UI pattern.
- Item 3: "Unload" label choice; no menu item; no confirmation dialog.

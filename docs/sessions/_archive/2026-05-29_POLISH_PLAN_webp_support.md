# POLISH_PLAN — WebP export support

Plan written 2026-05-29 via /ultrathink + 2 parallel research agents (SDWebImageWebPCoder recon + libwebp UX patterns) + direct SFV codebase recon. Mirrors `POLISH_PLAN_post_phase5.md` conventions.

## Goal

Add WebP as a fourth export format alongside PNG / JPG / HEIC. Use SDWebImageWebPCoder via SPM (user-chosen Option A). Surface the encoder's two meaningful capabilities: lossless vs lossy mode, and the quality/effort dial.

## Why now

User asked. The Phase-5 round dropped WebP because ImageIO can't write it on macOS through 26.5. That is still true, but the user has a paid Apple Developer Program account, so vendoring a third-party encoder via SPM is acceptable. Notarization, hardened runtime, and library signing all stay clean with SDWebImageWebPCoder (pure source build, no dlopen, no JIT).

## Key decisions

### 1. SDWebImageWebPCoder 0.15.0, accepting ~2 MB binary growth

v0.15.0 shipped 2025-11-03, added ICC-profile embedding on encode, actively maintained. Transitively pulls **SDWebImage core** (image-loading framework we don't otherwise use, ~1.2–1.8 MB after DCE) and **libwebp-Xcode** (~0.6–0.9 MB). Total ≈ 2 MB binary growth. Trade-off accepted because (a) maintenance is upstream, (b) we get the ICC-embed feature for free, (c) the alternative — depending directly on `libwebp-Xcode` and writing ~50 LOC of CGImage→RGBA→`WebPEncodeRGBA` bridging — adds owned C-interop surface we'd then maintain forever.

Future-shrink option logged but out of scope: swap to direct `libwebp-Xcode` if binary size ever becomes an issue.

### 2. Two controls: Quality slider + Lossless toggle

Matches Affinity Photo's minimalism. Squoosh and GIMP put image-hint and method dials behind "Advanced" — for short video stills the defaults are fine. The user's "whatever the encoder allows" reads as: expose the format's one bimodal decision (lossless?) and its one continuous dial (quality/effort), skip the long tail.

### 3. Quality slider reused; relabel "Effort" when WebP + lossless (user-confirmed 2026-05-29)

libwebp reuses the `quality` parameter as encoding effort when `lossless=1` (q=100 = slow + smallest file; q=0 = fast + larger). One slider, two semantic roles, conditional label flip — cleaner than two parallel sliders. Backing variable stays `exportQuality`. `.help()` tooltip explains the dual semantics so the label flip isn't mysterious.

### 4. Hardcode `method=6` on every WebP encode

SDWebImageWebPCoder issue #116 documents: default `method=4` produces visibly lower output than the `cwebp` CLI at the same `q`. Setting `SDImageCoderEncodeWebPMethod: NSNumber(value: 6)` closes the gap. CPU cost ≈ 2–3× per frame on arm64 vs method=4. Acceptable — SFV's design target is 30 s–2 min clips (see `docs/PROJECT_STATE.md` "What this is"), encoding latency is not a hot path.

### 5. Convert CGImage to sRGB before handing it to the encoder

`AVAssetImageGenerator` returns CGImages tagged with the video's color space (Rec.709 for SDR, BT.2020 for HDR sources). libwebp writes pixel data as-is; viewers without color management would see shifted colors. Convert via a transient `CGContext` backed by `CGColorSpace(name: CGColorSpace.sRGB)!` before wrapping in `NSImage`. Matches what `CGImageDestination` does implicitly for the existing PNG/JPG/HEIC paths. SDWebImageWebPCoder 0.15.0 will embed the sRGB ICC profile of the converted image, so color-managed viewers also stay correct.

### 6. `@preconcurrency import` for both modules

SDWebImage and SDWebImageWebPCoder are ObjC, headers not audited for Sendable. Under our `SWIFT_STRICT_CONCURRENCY=complete`, plain `import` triggers warnings on the options dict and on hopping `SDImageWebPCoder.shared` across actors. `@preconcurrency import SDWebImageWebPCoder` + `@preconcurrency import SDWebImage` suppresses cleanly. No upstream Swift 6 audit issue is tracking this; community treats it as source-compatible only with `@preconcurrency`.

### 7. Encode off the main actor — already free

`ExtractionPipeline.run`'s `for try await` loop runs off-main; `autoreleasepool` wraps the encode step. No isolation work needed; the new WebP branch slots into the same context.

## Knobs deliberately skipped

- **`image_hint`** (HINT_PHOTO / HINT_PICTURE / HINT_GRAPH) — affects lossless only; HINT_DEFAULT is fine for varied video content
- **`method` slider** — hardcoded to 6 per decision 4
- **`alpha_quality` / `alpha_compression` / `alpha_filtering`** — CGImages from `AVAssetImageGenerator` have no alpha channel for SFV's inputs
- **`sharp_yuv`** — improves Rec.709→YCbCr fidelity for skintones; default off matches cwebp; revisit only if a user reports color complaints
- **`near_lossless`** — preprocessing for lossless; default 100 (off) is the right choice for an extraction tool

## Files & changes

### `01_Project/project.yml` — add SPM dependency (~7 LOC added)

Append a `packages:` block at top level:

```yaml
packages:
  SDWebImageWebPCoder:
    url: https://github.com/SDWebImage/SDWebImageWebPCoder.git
    from: 0.15.0
```

And add to `targets.ScreenshotFromVideos`:

```yaml
    dependencies:
      - package: SDWebImageWebPCoder
        product: SDWebImageWebPCoder
```

Then `cd 01_Project && xcodegen generate`. Per `docs/decisions.md` (the entry queued from POLISH_PLAN_post_phase5), regen is required whenever sources or packages change.

### `01_Project/ScreenshotFromVideos/Models/ExportFormat.swift` — extend enum (~8 LOC)

- Add `case webp = "WebP"` to enum cases
- Add `case .webp: return .webP` to `utType` (kept for future ImageIO compatibility, not used by WebP write path)
- Add `case .webp: return "webp"` to `fileExtension`
- Add `case .webp: return true` to `supportsCompression`
- Add new computed: `var hasLosslessOption: Bool { self == .webp }`
- Update file header — drop the "WebP dropped" line, replace with: "WebP added in webp-support polish (uses SDWebImageWebPCoder, not ImageIO)"

### `01_Project/ScreenshotFromVideos/Models/ExtractionRequest.swift` — add lossless field (~1 LOC)

```swift
var lossless: Bool = false
```

### `01_Project/ScreenshotFromVideos/Services/WebPEncoder.swift` — NEW (~55 LOC)

Self-contained. Header notes the lift source (SDWebImageWebPCoder + the sRGB conversion pattern). API:

```swift
enum WebPEncoder {
    static func encode(_ cgImage: CGImage, to url: URL, quality: Double, lossless: Bool) throws
}
```

Implementation steps:
1. Convert input to sRGB via `CGContext(data: nil, width: …, height: …, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue)`. Draw the input, snapshot `makeImage()`.
2. Wrap as `NSImage(cgImage: srgbImage, size: .zero)`.
3. Build options dict:
   ```swift
   var opts: [SDImageCoderOption: Any] = [
       .encodeCompressionQuality: NSNumber(value: max(0, min(1, quality))),
       SDImageCoderEncodeWebPMethod: NSNumber(value: 6),
   ]
   if lossless { opts[SDImageCoderEncodeWebPLossless] = NSNumber(value: true) }
   ```
4. `guard let data = SDImageWebPCoder.shared.encodedData(with: nsImage, format: .webP, options: opts) else { throw ImageExportError.failedToWriteImage }`
5. `try data.write(to: url)`

Throws `ImageExportError.failedToWriteImage` on either nil encode or write failure.

### `01_Project/ScreenshotFromVideos/Services/ImageExportService.swift` — branch on format (~8 LOC)

Update signature: `writeImage(_:to:format:quality:lossless:)`. Branch at the top:

```swift
if format == .webp {
    try WebPEncoder.encode(cgImage, to: url, quality: quality, lossless: lossless)
    return
}
```

The existing `CGImageDestination` path handles PNG/JPG/HEIC unchanged.

### `01_Project/ScreenshotFromVideos/App/Preferences.swift` — persist lossless (~12 LOC)

- Add `static let exportLossless = "exportLossless"` to `Key`
- Add reader `static func exportLossless() -> Bool { defaults.bool(forKey: Key.exportLossless) }` — default false from `bool(forKey:)` for missing keys
- Add writer `static func setExportLossless(_ v: Bool) { defaults.set(v, forKey: Key.exportLossless) }`

### `01_Project/ScreenshotFromVideos/App/ExtractionViewModel.swift` — VM state + request flow (~6 LOC)

- Add `var exportLossless: Bool { didSet { Preferences.setExportLossless(exportLossless) } }`
- Read in `init()`: `self.exportLossless = Preferences.exportLossless()`
- Pass through in `buildRequest()`: append `lossless: exportLossless` to the `ExtractionRequest` init

### `01_Project/ScreenshotFromVideos/Core/ExtractionPipeline.swift` — forward the flag (~1 LOC)

Update the `writeImage` call site to pass `lossless: request.lossless`.

### `01_Project/ScreenshotFromVideos/UI/RightPaneView.swift` — UI controls (~14 LOC)

In `formatSection`, after the Quality slider HStack, conditionally add a Lossless toggle when the format supports it:

```swift
if vm.exportFormat.hasLosslessOption {
    Toggle("Lossless", isOn: $vm.exportLossless)
        .controlSize(.small)
        .help("Lossless WebP — bit-exact pixels, typically 25–35% smaller than PNG. The Quality slider becomes encoding effort: higher = smaller file, slower encode.")
}
```

Flip the slider's "Quality" label to "Effort" when WebP + lossless is on:

```swift
Text(vm.exportFormat == .webp && vm.exportLossless ? "Effort" : "Quality")
```

Slider range, step, and backing variable stay as-is — values still mean "0…1 maps to libwebp 0–100" regardless of semantic role.

## Sundry side-task surfaced during recon

`ExtractionViewModel.startExtraction` line 239 hardcodes the success message to `"wrote \(urls.count) PNG\(urls.count == 1 ? "" : "s")"` regardless of format. Pre-existing since the Item-2 multi-format ship — has been silently wrong for JPG and HEIC exports already. One-line fix: `"PNG"` → `request.format.rawValue`. Bundle into Wave B since we're already touching the request shape.

Catch: `startExtraction` doesn't currently hold the resolved `request`. The line lives inside the `do` block before the catch arms; `request` is in scope. Trivial.

## Implementation sequence (waves)

**Wave A — Wiring (build green, no functional change).** Add `packages:` + `dependencies:` to `project.yml`. Run `xcodegen generate`. Add a stub `Services/WebPEncoder.swift` with `@preconcurrency import SDWebImageWebPCoder` + a `throw ImageExportError.failedToWriteImage` body. Run `xcodebuild` — confirm SPM resolution succeeds, build is clean under `SWIFT_STRICT_CONCURRENCY=complete`, no Sendable warnings.

**Wave B — Encoder + model plumbing.** Flesh out `WebPEncoder.encode`. Extend `ExportFormat`. Add `lossless` to `ExtractionRequest`. Add `exportLossless` to `Preferences` + VM. Update `ImageExportService.writeImage` signature + branch. Update `ExtractionPipeline` call site. Fix the hardcoded "PNG" message. Build clean.

**Wave C — UI.** WebP button appears automatically from `ExportFormat.allCases`. Add conditional Lossless toggle. Conditional Quality ↔ Effort label flip. Build clean.

**Wave D — Smoke test.** From a short test clip (use a Rec.709 SDR source so the color-space conversion is visible if broken):
1. Export PNG (baseline) — keep one frame
2. Export WebP lossy @ q=0.5 → confirm `.webp` extension, opens in Preview, smaller than PNG
3. Export WebP lossy @ q=1.0 → confirm visibly higher quality than 0.5
4. Export WebP lossless @ slider=0.5 (label says "Effort") → confirm bit-exact: decoded RGBA bytes match the PNG export's RGBA bytes (compare via a quick `sips -s format png` round-trip + `shasum`)
5. Export WebP lossless @ slider=1.0 → confirm smaller file than slider=0.5 lossless (effort=100 vs effort=50)
6. `file *.webp` reports `RIFF (little-endian) data, Web/P image`
7. Reopen the saved `.webp` in Preview, look at colors against the PNG baseline — no obvious shift = sRGB conversion is working

Already-known good signals for the toggle: label flip happens, slider value persists across format switches, Lossless toggle persists across app relaunch.

**Wave E — Commit + ship.** One atomic commit on a fresh branch **`polish/webp-support`** (user-confirmed 2026-05-29 — keeps WebP cleanly separable for review/revert from the existing `polish/post-phase-5` polish round).

## Build & sign sanity

- **Universal binary**: SDWebImageWebPCoder is source-built via SPM; arm64 + x86_64 both compile into the app target automatically. No xcframework, no binaryTarget. ✓
- **Hardened runtime**: `ENABLE_HARDENED_RUNTIME=YES` untouched. SDWebImage is pure source — no dlopen, no JIT, no `cs.disable-library-validation` needed. ✓
- **Notarization**: third-party SPM sources sign with the app's Developer ID at bundle-sign time. No notarization-rejection reports on the upstream repo for SDWebImageWebPCoder. ✓
- **Code size growth**: ~2 MB on the app binary. Acceptable for a single-purpose utility.
- **xcodegen regen requirement**: per `docs/decisions.md`, the sources/packages glob is resolved at `xcodegen generate` time. `xcodegen generate` after editing `project.yml`. Confirmed during POLISH_PLAN_post_phase5 Item 2.

## Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| SDWebImage core's non-Sendable headers leak warnings into SFV compilation | High | `@preconcurrency import` on both modules |
| Encoded WebP looks washed-out (Rec.709 video frames written as untagged sRGB pixels) | Medium | Explicit sRGB CGContext conversion before encoder handoff; 0.15.0 also embeds the resulting sRGB ICC profile |
| Output quality differs from `cwebp` CLI baselines users may compare against | Medium | Send `method=6` explicitly per SDWebImageWebPCoder issue #116 |
| Encode slow at method=6 on long clips | Low | Acceptable — SFV's target is 30 s–2 min clips; fall back to method=2 if a real complaint surfaces |
| User expects animated WebP (single .webp containing all frames) | Low | Out of scope — SFV's contract is "N still images." If raised, add a separate plan: SDWebImageWebPCoder supports animated encode via `SDAnimatedImage` |
| macOS 26 / Tahoe regression | Low | 0.15.0 shipped post-Tahoe (Nov 2025 vs Sept 2025 release); no open issues reference 26-specific breakage |
| Future SPM dependency churn drags us into SDWebImage core upgrades we don't care about | Low | Pin via `from: 0.15.0` (allows 0.15.x patches, not 0.16.0+). Revisit on user request only |

## Estimated total LOC

~95 net added across **7 modified + 1 new** file. Parallels POLISH_PLAN_post_phase5 Item 2 (multi-format export, ~120 LOC).

## Out of scope for this plan

- Animated WebP export
- Per-frame quality variation
- Direct `libwebp-Xcode` wrapper to drop SDWebImage core (~1.5 MB shrink) — defer until binary size is a concrete concern
- WebP decode anywhere in the app
- `image_hint`, `method`, `alpha_quality`, `sharp_yuv` UI controls — defaults are fine; revisit per user complaint

## Decisions to promote to `docs/decisions.md` post-ship

1. WebP support via SDWebImageWebPCoder 0.15.0 + the ~2 MB binary trade-off
2. Quality slider reused as effort in lossless mode (label flips, value semantic stays "0–1 → libwebp 0–100")
3. `method=6` hardcoded per SDWebImageWebPCoder #116
4. sRGB CGContext conversion before encoder handoff
5. `@preconcurrency import` pattern for SDWebImage modules under SWIFT_STRICT_CONCURRENCY=complete

# Icon Integration — engineering side of the handoff

**Audience: this repo** (Claude Code or the developer). What to do when Claude
Design returns the assets described in `HANDOFF.md` §6.

## Where the icon lives

- Asset catalog: `01_Project/ScreenshotFromVideos/Assets.xcassets/AppIcon.appiconset/`
- 10 classic slots (16→512@2x) declared in that folder's `Contents.json` — the
  filenames there are the contract; don't rename slots, replace file contents.
- Wired via `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `01_Project/project.yml`
  (already set — no project.yml change needed for a same-shape replacement).

## Steps

1. **Sanity-check the delivered master** (`stills-from-video-icon-1024.png`):
   - 1024×1024, PNG, sRGB.
   - Rounded square ~824×824 centered, transparent outside it (per brief §5.1).
     If it arrived full-bleed, push back — don't shrink it yourself with `sips`,
     resampling the plate softens the corners.
2. **Replace the master slot:**
   ```bash
   cp stills-from-video-icon-1024.png \
      01_Project/ScreenshotFromVideos/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
   ```
3. **Regenerate the 9 smaller slots** (from repo root, macOS only — uses `sips`):
   ```bash
   ICONSET=01_Project/ScreenshotFromVideos/Assets.xcassets/AppIcon.appiconset
   MASTER=$ICONSET/icon_512x512@2x.png
   for spec in "16:icon_16x16.png" "32:icon_16x16@2x.png" \
               "32:icon_32x32.png" "64:icon_32x32@2x.png" \
               "128:icon_128x128.png" "256:icon_128x128@2x.png" \
               "256:icon_256x256.png" "512:icon_256x256@2x.png" \
               "512:icon_512x512.png"; do
     px="${spec%%:*}"; name="${spec##*:}"
     sips -z "$px" "$px" "$MASTER" --out "$ICONSET/$name" > /dev/null
   done
   ```
4. **Archive the delivery**: keep the returned files (master + layers + rationale)
   in `02_Design/ICON_HANDOFF/delivery/` and commit them — the layers are the
   source for the future Icon Composer / `.icon` migration (brief §5.2).
5. **Rebuild & verify**: `cd 01_Project && xcodegen generate && xcodebuild build …`
   No `xcodegen` change is strictly needed for replaced PNGs, but regen is this
   repo's standing habit and harmless. Check the Dock icon at small size and
   ⌘-Tab switcher.
6. **Retire the placeholder generator**: once the designed icon lands,
   `02_Design/generate_app_icon.swift` is reference-only. Leave it (history) or
   delete it — either is fine; if it stays, don't re-run it (it would overwrite
   the designed master).
7. **If the icon-relevant caches act up** (old icon keeps showing):
   `killall Dock` usually suffices; otherwise it's the standard iconservices
   cache and a logout fixes it.

## Later: macOS 26 / Icon Composer migration (not now)

When the toolchain moves to Xcode 26+, assemble the delivered layers in Icon
Composer into a `.icon` file, add it to the project, and point
`ASSETCATALOG_COMPILER_APPICON_NAME` / the icon build setting per Xcode 26 docs.
The classic appiconset stays as the fallback for older macOS. This is why §5.2
of the brief asks for separable layers — do not lose them.

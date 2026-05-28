# Claude Design — prompt for Stills From Video app icon

Paste the block below into Claude Design (or any AI image tool that outputs 1024×1024 PNGs) when you want to replace the placeholder icon.

---

## Prompt

> Design a macOS application icon, 1024×1024 px, in the modern macOS Sequoia/Tahoe icon style: a rounded square canvas with soft material depth (no hard photorealism, no skeuomorphism, no glassy reflections). The app is called **Stills From Video** — it extracts still frames from any video file (screen recordings, .mov, .mp4) and writes them as PNGs.
>
> Visual concept: a stylized **film strip** (3-4 frames visible) with one frame visibly **detached and lifted out** of the strip — gentle rotation, soft shadow under it, slight color shift on that one frame so it reads as "this is the extracted still." The icon must read clearly at 32×32 (Dock proxy / menu bar) — keep the silhouette punchy with no fine detail in the lower-third of the canvas.
>
> Palette: dark navy / slate background (think `#1a2233` → `#2a3441`), a single bright accent (warm amber or off-white) for the "captured frame" highlight. Avoid pure black background. Avoid more than two accent colors.
>
> Composition: centered subject, leave ~120 px of breathing room from each edge, do not let any element touch the rounded corners. No text in the icon (the system shows the app name).
>
> Style: flat-ish with subtle interior shadow / highlight for depth, NOT a sticker, NOT a photograph, NOT a render of a physical camera.
>
> Deliver as a square 1024×1024 PNG with transparency disabled (opaque background drawn to the rounded corners).

---

## After you get the 1024 PNG back

1. Save it as `01_Project/ScreenshotFromVideos/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` (replace the placeholder).
2. From the project root, regenerate the smaller sizes:
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
3. Rebuild the app (`cd 01_Project && xcodegen generate && xcodebuild build …`).

The placeholder generator (`02_Design/generate_app_icon.swift`) is preserved for reference but you don't need to re-run it once a polished master replaces it.

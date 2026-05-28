# ScreenshotFromVideos

macOS app that extracts frames from a video as PNGs — every Nth frame or user-selected timestamps — with optional timestamp overlay and chronological filename numbering.

## Why
Claude Code can't read video. When you want to share what's happening in a screen recording, you need stills. This app turns a video into a folder of frames ready to drop into a prompt.

## Status
Early scaffolding. See `docs/PROJECT_STATE.md`.

## Build
```bash
cd 01_Project
xcodegen generate
open ScreenshotFromVideos.xcodeproj
```

Requires macOS 15.0+, Xcode 16+, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

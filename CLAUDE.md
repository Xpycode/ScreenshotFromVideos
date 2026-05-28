# ScreenshotFromVideos — Project Instructions

## What Is This
macOS app that extracts frames from a video as PNGs — every Nth frame or user-selected timestamps — with optional timestamp overlay and chronological filename numbering. Born from wanting to share what's happening in screen recordings with Claude Code (which can't read video).

**Read `docs/PROJECT_STATE.md` for current status.**

## Tech Stack
- macOS 15.0+ / Swift 6.0 / SwiftUI
- Xcode 16+
- Notarized for distribution (not sandboxed)
- Hardened runtime enabled

## Project Structure
```
01_Project/      — Xcode project + source (project.yml drives xcodegen)
02_Design/       — Design assets
03_Screenshots/  — App screenshots for README
04_Exports/      — Built .app and .dmg
docs/            — Directions documentation system (sessions, decisions, PROJECT_STATE)
```

## Build Tooling
- **xcodegen** drives `.xcodeproj` from `01_Project/project.yml`
- Regenerate: `cd 01_Project && xcodegen generate`
- The `.xcodeproj` is generated — edit `project.yml`, not the pbxproj

## Code Lineage
This app reuses code from two sibling published apps:
- **VideoWallpaper** → AVFoundation video loading, frame generation, drag-drop, file picker, progress UI
- **CropBatch** → PNG writing, text overlay (timestamps), filename templating, batch Task pattern, app shell

See `docs/PROJECT_STATE.md` "Liftable Code Inventory" for the file-by-file map.

## Conventions
- Bundle ID: `com.lucesumbrarum.ScreenshotFromVideos`
- Team: FDMSRXXN73
- Feature branches: `feature/name` or just `name`
- "Works for me" polish level — don't over-engineer edge cases

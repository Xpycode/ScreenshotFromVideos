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


<!-- DIRECTIONS-PROJECT:START -->
## Shared Directions workflow

- **Local master:** `/Users/sim/ProgrammingProjects/0-DIRECTIONS/__DIRECTIONS`.
- For Directions commands, use the installed Directions skill in Codex or read the master's
  `commands/<name>.md` completely. Slashless forms work too. Approved-plan continuation uses
  `commands/execute.md`; status alone does not authorize execution.
- Resolve shared `reference/...` from that master. Read universal guidance there on demand;
  use the relevant host global template's routing section if global guidance is unavailable.
  Report a missing master instead of using copied universal guides.
- This section supersedes older generic Directions workflow, copied-guide loading, automatic
  app-control and PR-ceremony instructions in this file. Preserve project-specific architecture,
  build commands, security constraints and product requirements above.
- Retained numbered guides in `docs/` are legacy references, not workflow authority. Preserve
  their project-specific additions; consult them only for relevant historical/project evidence.
- Preserve existing state, selected plans, open gates and session history. Legacy task/state
  reconciliation is separate work; never mark a manual gate complete from an old checkbox.
- Before builds/tests, read the master's `34_testing.md` and inspect startup effects. Desktop/app
  control requires explicit user permission; older automatic quit/launch instructions do not grant it.
  Give full absolute paths for user-operated file/app steps. Preserve dirty work and user limits.
<!-- DIRECTIONS-PROJECT:END -->

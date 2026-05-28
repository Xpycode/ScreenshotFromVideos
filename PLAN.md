# PLAN

## Phase 1 — Scaffold ✅
- xcodegen project, minimal SwiftUI shell, asset catalog, docs structure

## Phase 2 — Lift
Copy reusable files from `_Published/VideoWallpaper` and `_Published/CropBatch` into the project, adapt namespaces and dependencies.

## Phase 3 — Glue
Three small pieces only:
- Extraction loop iterating `[CMTime]` over the single-frame generator
- `CMTime` → `"00:01:23.456"` formatter
- Per-frame pipeline: extract → optional overlay → optional numbering → write PNG

## Phase 4 — UI
Minimal SwiftUI window:
- Drop / pick video
- Pick interval (every N seconds / every N frames) OR custom timestamp list
- Toggle: timestamp overlay
- Toggle: chronological numbering in filename
- Pick output folder
- Export with progress and cancel

## Out of scope (for now)
- Video editing, trimming, conversion
- Multi-video batch
- Cloud upload
- Custom overlay styling beyond defaults

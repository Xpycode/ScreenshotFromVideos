# PROJECT_STATE — ScreenshotFromVideos

*Last updated: 2026-11-06 — performance plan closed and archived; footer follow-up remains separate.*

## Identity
macOS app that extracts still frames from a video as PNGs — every Nth frame or hand-picked timestamps — with optional timestamp burn-in and chronological filename numbering. Built to feed Claude Code visual context from screen recordings. Also exports JPG / HEIC / WebP.

- **User-facing name:** "Stills From Video" (since 2026-05-27). Internal IDs stay `ScreenshotFromVideos` (bundle `com.lucesumbrarum.ScreenshotFromVideos`, team `FDMSRXXN73`).
- **Design target:** short clips, 30 s–2 min. Longer clips work but the strip renders slower; multi-hour optimization is explicitly out of scope.
- **Packages:** adopt MediaKit + FolderAccessKit · source for MediaKit + ImageIOKit — see `docs/PACKAGE-NOTES.md`.

## Now
- **Phase:** polish after the completed strip/player performance pass.
- **Focus:** finish the separate compact-footer verification before choosing the next backlog item.
- **Plan:** none active; [performance archive](sessions/_archive/2026-11-06_STRIP_PLAYER_PERFORMANCE_PLAN.md) records 14 completed tasks and one reverted experiment.
- **Blockers:** none for performance closeout; footer wide-label/tooltips/action checks remain unreported.
- **Next:** finish the finite compact-footer checks, then checkpoint that change separately. Run `/check ship` before release.
- **Current handoff:** [2026-11-06 closeout Resume](sessions/2026-11-06.md#resume--performance-plan-complete).

## Recent
- **2026-11-06** — Fresh build and user-confirmed CPU samples complete; independent review found no source defect. Performance plan archived with 14 completed tasks and one reverted experiment.
- **2026-11-02** — Resumed Wave 4; user retained progressive fill and revised refresh criterion. Accepted source/artifact checksums match; current-artifact CPU collector prepared.
- **2026-11-01** — Fixed visible-cell demand, then reproduced an isolated decoder hole and added one fresh retry: real fixture improves 11/12→12/12. Strict build/review pass; manual matrix user-passed; performance closeout remains.
- **2026-10-29** — Two-minute paused failure reproduced; first trace capped before zoom. Focused trace rebuilt and smoke-verified; repeat capture pending.
- **2026-10-29** — Wave 4 found persistent black selected thumbnail after paused zoom; screenshot/report saved. CPU samples collected; final acceptance remains open.

## Backlog (none blocking)
- **Perf tuning ideas:** raise default zoom 1.0 → ~3 for a friendlier first view; re-tune prefetch pads for the grid layout; tune the 256 in-flight decode cap per hardware.
- **Polish queue:** notarized DMG for distribution; install selected [stacked app icon v3](../02_Design/Icon-2026-10-28/stills-from-video-candidate-v3-1024.png) and generate all icon sizes (design accepted, not yet installed); optional diagnostic logging.
- **Light-mode toggle (deferred):** app is hard-coded `.preferredColorScheme(.dark)`. Plan: `@AppStorage("colorScheme")` (system/light/dark) → `.preferredColorScheme(...)` in the app shell; for true per-scheme colors, `Theme` must become an `EnvironmentKey`-backed struct (see `decisions.md` §4).

## Infrastructure
- **Remote:** public GitHub `origin` → https://github.com/Xpycode/ScreenshotFromVideos (`main` tracking).
- **Signing on this Mac:** holds the Developer ID cert `GREGOR MÜLLER (FDMSRXXN73)` (can notarize a v0.1 DMG) but NOT the Sparkle `o388…` auto-update private key — so `scripts/release.sh` refuses here; an auto-update release must be cut on the Mac holding `o388…`. Local dev builds need ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) — no Apple Development cert here. Bump `CURRENT_PROJECT_VERSION` every release.
- **Build:** xcodegen drives the `.xcodeproj` from `01_Project/project.yml`; run `cd 01_Project && xcodegen generate` after adding/moving any `.swift` file.

## Detail (read only if needed)
- **Decisions + rationale** → `docs/decisions.md` (§1–§8, plus a 2026-07-18 Condensed Log of three migrated entries).
- **Session-by-session history** → `docs/sessions/_index.md`.
- **Completed performance plan** → [archive](sessions/_archive/2026-11-06_STRIP_PLAYER_PERFORMANCE_PLAN.md); [evidence index](sessions/_archive/2026-11-06_STRIP_PLAYER_PERFORMANCE_EVIDENCE.md).

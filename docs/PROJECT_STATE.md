# PROJECT_STATE — ScreenshotFromVideos

*Last updated: 2026-11-13 — pre-clear handoff; #4 and new icon user-passed, first release renumbered to 1.0 (build 1000).*

## Identity
macOS app that extracts still frames from a video as PNGs — every Nth frame or hand-picked timestamps — with optional timestamp burn-in and chronological filename numbering. Built to feed Claude Code visual context from screen recordings. Also exports JPG / HEIC / WebP.

- **User-facing name:** "Stills From Video" (since 2026-05-27). Internal IDs stay `ScreenshotFromVideos` (bundle `com.lucesumbrarum.ScreenshotFromVideos`, team `FDMSRXXN73`).
- **Design target:** short clips, 30 s–2 min. Longer clips work but the strip renders slower; multi-hour optimization is explicitly out of scope.
- **Packages:** adopt MediaKit + FolderAccessKit · source for MediaKit + ImageIOKit — see `docs/PACKAGE-NOTES.md`.

## Now
- **Phase:** shipping — v1.0 release prep. <!-- Phase changed: 2026-11-12 -->
- **Focus:** v1.0 release (renumbered from the never-shipped 0.1 on 2026-11-13; build 1000). Ship check found 0 code blockers; export-failure fix (#4) and new Dock icon user-passed 2026-11-12.
- **Plan:** v1.0 release — see `TASKS.md` Active plan (from `/check ship` 2026-11-09). Prior: [performance archive](sessions/_archive/2026-11-06_STRIP_PLAYER_PERFORMANCE_PLAN.md) records 14 completed tasks and one reverted experiment.
- **Blockers:** none for the completed performance and footer work.
- **Next:** decide + resolve the About Website link (publish portal page or remove), then cut the notarized DMG on the Mac holding the Sparkle key.
- **Done for v1.0** (proposed by `/check ship` 2026-11-09; 0 code ship-blockers, 3 release gates not run):
  - [ ] A notarized, stapled DMG built from the release commit installs and runs on a clean account
  - [ ] Interval and Manual exports write the expected frame count, and failures are reported to the user *(failure reporting + Manual passed 2026-11-12; Interval to confirm in the DMG smoke test)*
  - [ ] The appcast has a Sparkle-signed v1.0 item, or v1.0 is explicitly released without auto-update
  - [ ] The About Website link resolves, or is removed for v1.0
  - Everything else → v1.1.
- **Current handoff:** [2026-11-13 pre-clear Resume](sessions/2026-11-12.md#resume-2026-11-13-pre-clear).

## Recent
- **2026-11-12/13** — Ship check: no code blockers, release steps still to run. Built a fix so failed or missing-folder exports are reported honestly (user-passed), and switched the app icon to an Icon Composer file so the Dock no longer shows it on a grey tile. Both user-passed; first release renumbered 1.0 (build 1000).
- **2026-11-09** — Appearance menu (Match System / Light / Dark) with a full light theme, user-accepted. Found feedback and tips already working; published a shared privacy page the apps' About panels link to, and fixed Magpie's wrong feedback-privacy claim.
- **2026-11-08** — App-citizenship pass: Feedback/Tip/About (AppCitizenshipKit), Help menu (vendored HelpMenu + 9 topics, Command-?), `.app` renamed to "Stills From Video.app" (internal IDs kept). Merged the performance branch into main and pushed. Installed the v3 stacked app icon, scaled to match sibling icons in the Dock (835 px body on a 1024 px canvas), all 10 sizes; build verified.
- **2026-11-07** — Pre-clear handoff saved: footer accepted and committed locally; next suggested work is selected icon integration.
- **2026-11-06** — Fresh build and user-confirmed CPU samples complete; independent review found no source defect. Performance plan archived with 14 completed tasks and one reverted experiment. Compact footer/native hover tips also user-accepted after strict build.

## Backlog (none blocking)
- **Perf tuning ideas:** raise default zoom 1.0 → ~3 for a friendlier first view; re-tune prefetch pads for the grid layout; tune the 256 in-flight decode cap per hardware.
- **Polish queue:** notarized DMG for distribution; optional diagnostic logging.

## Infrastructure
- **Remote:** public GitHub `origin` → https://github.com/Xpycode/ScreenshotFromVideos (`main` tracking).
- **Signing on this Mac:** holds the Developer ID cert `GREGOR MÜLLER (FDMSRXXN73)` (can notarize a DMG) but NOT the Sparkle `o388…` auto-update private key — so `scripts/release.sh` refuses here; an auto-update release must be cut on the Mac holding `o388…`. Local dev builds need ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) — no Apple Development cert here. Bump `CURRENT_PROJECT_VERSION` every release (house scheme: 1.0 → 1000, 1.1 → 1100).
- **Build:** xcodegen drives the `.xcodeproj` from `01_Project/project.yml`; run `cd 01_Project && xcodegen generate` after adding/moving any `.swift` file.

## Detail (read only if needed)
- **Decisions + rationale** → `docs/decisions.md` (§1–§8, plus a 2026-07-18 Condensed Log of three migrated entries).
- **Session-by-session history** → `docs/sessions/_index.md`.
- **Completed performance plan** → [archive](sessions/_archive/2026-11-06_STRIP_PLAYER_PERFORMANCE_PLAN.md); [evidence index](sessions/_archive/2026-11-06_STRIP_PLAYER_PERFORMANCE_EVIDENCE.md).

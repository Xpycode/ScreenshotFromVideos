# ICON_HANDOFF — app icon design handoff package

Self-contained handoff so **Claude Design** can create the proper, modern macOS
app icon for **Stills From Video** (replacing the code-generated placeholder).

| File | For whom | What |
|---|---|---|
| `HANDOFF.md` | Claude Design | The full design brief: app identity, palette, concept to keep, macOS icon grid/format requirements, deliverables list |
| `reference/current-placeholder-icon-1024.png` | Claude Design | Today's placeholder icon (concept reference; execution to be replaced) |
| `reference/mainWindow1-Manual.png`, `reference/mainWindow2-Interval.png` | Claude Design | Real app screenshots for visual context |
| `INTEGRATION.md` | this repo | How to wire the returned assets into the asset catalog |
| `delivery/` (created on return) | this repo | Where the returned master + layers get archived |

**To hand off:** give Claude Design this entire folder (or `HANDOFF.md` +
`reference/` if size matters). The brief is standalone — no repo access needed.

**On return:** follow `INTEGRATION.md`.

Supersedes `02_Design/CLAUDE_DESIGN_PROMPT.md` (kept with a pointer banner).

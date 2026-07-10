# App Icon Design Brief — "Stills From Video"

**Audience of this document: Claude Design** (or any designer/design agent).
This brief is self-contained — everything you need is in this folder. You do not
need access to the app's source code.

- Reference images live in `reference/` (current placeholder icon + two app screenshots).
- What to deliver and in which format: see **§6 Deliverables**.
- The engineering side of the handoff (how your files get wired into the app) is
  `INTEGRATION.md`, one folder up in the package — you can ignore it.

---

## 1. The app

**Stills From Video** is a small, focused macOS utility (macOS 15+, dark-only UI).
It does one thing: load a video, pick frames — every Nth frame, or hand-picked
timestamps while scrubbing a thumbnail contact sheet — and export them as
PNG/JPG/HEIC/WebP stills, optionally with the timestamp burned into the image.

It was born from a concrete need: sharing what happens *inside* a screen recording
with an AI coding assistant that can read images but not video. So the core gesture
of the app is: **a video goes in, individual frames get lifted out.**

Personality and positioning:

- A **pro-flavored utility**, not a toy. The UI borrows Final Cut Pro idioms
  (J/K/L shuttle keys, dark panels, timecode readouts) but stays deliberately small.
- Quick, precise, unglamorous. Think "scalpel", not "studio suite".
- Developer/publisher: Luces Umbrarum (indie, one-person). Sibling apps:
  VideoWallpaper, CropBatch — no enforced family style, so no constraint there.

Look at `reference/mainWindow1-Manual.png` and `reference/mainWindow2-Interval.png`
to absorb the app's actual visual world: near-black panels, a grid of video
thumbnails, an orange-highlighted selected frame, a big timecode overlay.

## 2. Brand color context

From the app's actual theme code:

| Role | Value | Notes |
|---|---|---|
| App accent | `#E68033` (≈ orange) | Selection borders, active states, export button tint |
| Primary background | `#1A1A1A` | Main window panels |
| Secondary background | `#262626` | Inset panels |

The current **placeholder icon** uses a different, cooler palette (navy
`#1A2133 → #293342` gradient, light-gray filmstrip `#D1D6DE`, warm-amber lifted
frame `#F5CF5C`). You are free to keep that palette, move toward the in-app
orange `#E68033`, or propose something better — but stay dark-grounded with
**one** warm accent. The accent belongs on the *extracted frame*, because that's
the story.

## 3. What exists today (and what's wrong with it)

`reference/current-placeholder-icon-1024.png` is a programmatically generated
placeholder: vertical filmstrip with sprocket holes, three empty frame windows,
and one warm-amber frame tilted ~6° lifting off the top-right.

**The concept is right — keep it.** Filmstrip + one frame visibly detached reads
instantly as "extract stills from video". What needs a designer:

1. **It fills the entire 1024 canvas edge-to-edge.** Standard macOS icons draw
   their rounded square at 824×824 centered in the 1024 canvas (~100 px margin
   each side). The placeholder therefore looks oversized and misaligned next to
   every other icon in the Dock. This must be fixed (see §5 grid spec).
2. **It's geometrically flat/programmatic.** No material depth, no lighting
   logic, no considered corner treatment — it looks like what it is: shapes
   drawn by code.
3. **The lifted frame is empty.** An empty amber rectangle reads as a sticky
   note at small sizes. Consider giving the lifted frame a hint of *content*
   (an abstract image suggestion — a gradient landscape, a play-glyph ghost,
   anything minimal) so it reads as "a captured picture", not "a Post-it".
4. **No dark-mode / tinted consideration.** See §5.

## 4. Design direction

- **Keep**: dark ground, filmstrip motif, one frame lifted out with rotation +
  shadow as the hero gesture, single warm accent, no text anywhere in the icon.
- **Modernize**: this should sit comfortably in a 2026 macOS Dock — the current
  system look is **Liquid Glass** (macOS 26 "Tahoe"): softly dimensional layers,
  restrained translucency, light coming from above, gentle interior
  shadows/highlights. Not flat-design 2015, not skeuomorphic 2010, not a
  sticker, not a photorealistic camera/film render.
- **Silhouette first**: the icon must read at 16×16 (Finder list view) and
  32×32 (Dock at small sizes). Squint test: dark rounded square, lighter strip,
  one bright tilted rectangle escaping it. If a detail doesn't survive 32 px,
  it's decoration — fine, but it must not carry meaning.
- Composition roughly centered; the lifted frame may break toward a corner for
  energy but **nothing touches the squircle edge**.

## 5. Hard technical requirements

### 5.1 Canvas & grid (classic macOS icon, required)

- Master artwork: **1024×1024 px PNG**, sRGB color profile.
- Draw the icon as a **rounded square of 824×824 px, centered** (100 px margin
  on all sides), **corner radius ≈ 185 px**. Everything outside the rounded
  square is **fully transparent**.
- A subtle baked drop shadow under the rounded square (à la Apple's Big Sur+
  template: soft, small offset, low opacity) is welcome but optional. The
  lifted-frame's own shadow is part of the design, keep that one.
- No alpha *inside* the plate — the rounded square itself is opaque.
- **No text**, no version numbers, no Apple hardware imagery.

The app ships this as a classic `AppIcon.appiconset` (10 slots from 16×16 to
512×512@2x, all downsampled from your 1024 master), so make sure fine details
(sprocket holes etc.) degrade gracefully rather than turning to noise.

### 5.2 Layered source (strongly encouraged, forward-looking)

macOS 26 introduced **Icon Composer** and the layered `.icon` format (Liquid
Glass renders the layers with real depth, and supplies dark/clear/tinted
variants). This project still builds with Xcode 16, so a `.icon` file can't be
consumed *yet* — but the moment the toolchain moves to Xcode 26 it will be.

So, if you can, deliver the artwork **as separable layers** in addition to the
flat master:

- Layer 1 (back): background plate / gradient
- Layer 2 (mid): filmstrip body (holes + frame windows)
- Layer 3 (front): the lifted/extracted frame with its shadow

Format: individual full-canvas 1024×1024 PNGs with transparency (or SVG if the
shapes are vector). Name them `layer-1-background.png`, `layer-2-filmstrip.png`,
`layer-3-lifted-frame.png`.

Design consequence even for the flat icon: keep the three planes visually
separable (no cross-layer texture that welds them together), so the future
Liquid Glass version is an assembly job, not a redesign.

### 5.3 Legibility checkpoints

Before delivering, verify the master downsampled to 32×32 and 16×16:

- [ ] Lifted frame still distinguishable from the strip
- [ ] Strip reads as "film/video", not "ladder/window blinds"
- [ ] Accent color survives (not muddied into the background)
- [ ] Overall shape matches the size/weight of neighboring stock macOS icons

## 6. Deliverables

| # | File | Required? |
|---|---|---|
| 1 | `stills-from-video-icon-1024.png` — flat master per §5.1 | **Required** |
| 2 | `layer-1-background.png`, `layer-2-filmstrip.png`, `layer-3-lifted-frame.png` (or SVGs) per §5.2 | Encouraged |
| 3 | One-paragraph rationale: palette choice + anything intentionally changed from this brief | Nice to have |

Hand the files back into this folder (a `delivery/` subfolder is fine) or
however the handoff channel works — the engineering side takes it from there
(`INTEGRATION.md`).

## 7. Explicitly out of scope

- Marketing/website art, DMG background, README banner (may come later)
- App Store assets (app is direct-distribution, notarized DMG)
- Renaming or re-theming the app itself
- Animated/dynamic icon variants

# Release Runbook — Stills From Video

End-to-end steps to ship a release. **Run on the Mac that holds the `o388…`
Sparkle private key** (see `docs/sparkle-signing.md`). The Mac this repo was
last edited on does **not** have that key.

---

## One-time setup on the release Mac

1. **Developer ID cert** — import `99-AUTH/AppleDevCertM1max.p12` into the login
   Keychain (needed for the `developer-id` export signing).

2. **Sparkle key** — confirm the `o388…` key is present:
   ```bash
   GK=$(find ~/Library/Developer/Xcode/DerivedData -path "*Sparkle/bin/generate_keys" | head -1)
   "$GK" -p     # must print o388Mk7QoQjHQ7PBDGrTQ13HkqvO1nyzkfcnmfVumUQ=
   ```
   If it doesn't, import it (`"$GK" -f <backup>`), per `docs/sparkle-signing.md`.

3. **notarytool profile** — store the App Store Connect API key once. Creds are in
   `99-AUTH/` (key `AuthKey_6HTCUZ9L7L.p8`, Key ID `6HTCUZ9L7L`, Issuer ID in
   `99-AUTH/IssuerID.rtf`):
   ```bash
   xcrun notarytool store-credentials notarytool \
     --key   /path/to/99-AUTH/AuthKey_6HTCUZ9L7L.p8 \
     --key-id 6HTCUZ9L7L \
     --issuer "<issuer-id from 99-AUTH/IssuerID.rtf>"
   ```

4. **Resolve packages once** — open the project in Xcode (or build it) so the
   Sparkle SPM tools land in DerivedData. `xcodegen generate` in `01_Project`
   first if needed.

---

## Per release

### 1. Bump versions (in `01_Project/project.yml`)

```yaml
MARKETING_VERSION: "0.2"        # the human version
CURRENT_PROJECT_VERSION: "2"    # MUST increase every release — Sparkle compares this
```

⚠️ **If you forget to bump `CURRENT_PROJECT_VERSION`, Sparkle won't offer the
update** even though the appcast lists it. This is the #1 release-day mistake.

Commit the bump.

### 2. Build, notarize, sign — one command

```bash
./scripts/release.sh            # reads the version from project.yml
# or: ./scripts/release.sh 0.2
```

This regenerates the project, archives, exports Developer ID, builds
`StillsFromVideo-<version>.dmg`, notarizes + staples it, signs it for Sparkle,
drops it in `releases/`, and prints the `appcast.xml` `<item>`.

### 3. Update the appcast

Paste the printed `<item>` into `appcast.xml` **newest first** (inside the
`<channel>`, above older items). Commit + **push to `main`** — the feed URL
points at `raw.githubusercontent.com/.../main/appcast.xml`, so the live feed is
whatever is on `main`.

### 4. Publish the GitHub Release

- Tag `v<version>` on `Xpycode/ScreenshotFromVideos`.
- Upload `releases/StillsFromVideo-<version>.dmg` — the filename **must match**
  the `enclosure url` in the appcast item.
- Publishing the release makes the README download badges + the GitHub download
  counter light up.

### 5. Verify

- Fresh download → open DMG → drag to Applications → launch → no Gatekeeper
  warning (notarization stapled correctly).
- On a machine running the previous version: **Check for Updates…** offers the
  new one and installs it (proves the signature validates against `o388…`).

---

## First release (v0.1) specifics

- `CURRENT_PROJECT_VERSION` is already `1` → the v0.1 appcast item uses
  `sparkle:version=1` (release.sh fills this from the built app).
- v0.1 ships *with* the updater already embedded, so v0.2 will be the first
  auto-update users receive.

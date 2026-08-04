# Releasing Lesson Lab

How a build on this machine becomes a download teachers can install and that
updates itself. The moving parts:

| Piece | Where | Why |
|---|---|---|
| DMG + update zips + model | GitHub Releases (`xq-labs/xq-lesson-lab`) | Free, 2 GB/file, no bandwidth charges |
| `appcast.xml` (Sparkle feed) + landing page | Vercel (`website/`) | Stable URL the app polls for updates |
| Version numbers + URLs | `TeacherWorkspace/Sources/TeacherWorkspace/AppInfo.swift` | Single source of truth — scripts read it |

The app ships **small** (~15 MB): the 1.2 GB model is downloaded on first
launch from a fixed-tag GitHub release (`model-qwen3.5-2b`), verified by
SHA-256 (`AppInfo.modelSHA256`), and installed under
`~/Library/Application Support/LessonLab/Models/`.

## One-time setup

### 1. Apple Developer Program + certificate — DONE (2026-07-31)
Douglas's personal account: Apple ID `ifdouglas@icloud.com`, team ID
`6NYH4QMV76` (Individual membership, renews Sept 2026). The
**"Developer ID Application: Douglas Fernandes (6NYH4QMV76)"** certificate
(expires 2031/08/01) and its private key are in Douglas's login keychain.
⚠️ Back up the identity: Keychain Access → My Certificates → right-click the
Developer ID cert → Export as .p12 (that bundle contains the private key —
without a backup, losing this Mac means revoking and re-issuing).
Switching to an XQ org account later is a normal Sparkle update signed by
the new cert (same Sparkle key = continuity).

### 2. Notarization credentials
Create an app-specific password at account.apple.com (Sign-In & Security →
App-Specific Passwords), then:
```bash
xcrun notarytool store-credentials xq-lesson-lab \
  --apple-id ifdouglas@icloud.com --team-id 6NYH4QMV76
```
(it prompts for the app-specific password; nothing is stored in the repo)

### 3. Sparkle signing keys — DONE (2026-07-31, Douglas's Mac)
Keys were generated with the tools that ship inside the Sparkle SPM artifact
(`TeacherWorkspace/.build/artifacts/sparkle/Sparkle/bin/` — also has
`generate_appcast` and `sign_update`; no separate download needed). The
public key is baked into make-app.sh; the **private key is in Douglas's
login keychain** ("Private key for signing Sparkle updates").
⚠️ Back it up (Keychain Access → export, or `generate_keys -x file`) — losing
it strands every installed app on its current version. Releasing from a
different Mac means importing it there (`generate_keys -f file`).

### 4. GitHub + Vercel
- Create the public repo `xq-labs/xq-lesson-lab` (or pick another name and
  update `AppInfo.githubRepo`, `website/index.html`, and this file).
- Upload the model once:
  `gh release create model-qwen3.5-2b TeacherWorkspace/Models/Qwen3.5-2B-Q4_K_M.gguf --title "Model: Qwen3.5-2B" --notes "Downloaded by the app on first launch."`
- On vercel.com: **Add New Project → import the repo → Root Directory =
  `website/`** (no build command, it's static). The default project name
  (`xq-lesson-lab`) gives `xq-lesson-lab.vercel.app`, which is what
  `AppInfo.websiteURL` expects — if you rename it or add a custom domain,
  update `AppInfo.websiteURL` + rebuild.

## Every release

1. Bump `AppInfo.version` (marketing) and `AppInfo.build` (monotonic integer —
   Sparkle compares this one).
2. ```bash
   cd TeacherWorkspace
   SIGN_IDENTITY="Developer ID Application: Douglas Fernandes (6NYH4QMV76)" \
   NOTARY_PROFILE=xq-lesson-lab \
   scripts/make-release.sh
   ```
   Builds, signs (hardened runtime), notarizes, staples, and produces
   `release/v<version>/` with `Lesson-Lab.dmg` + `Lesson-Lab-<version>.zip`.
3. Run the `generate_appcast` command the script prints — it signs the zip
   with your private key and emits `appcast.xml` (+ `.delta` files against
   the previous release, which is what keeps updates small).
   Two fixups the generator can't know about: it rewrites *every* entry's URL
   with the prefix you pass, so restore the **previous** release's enclosure
   URL (and `pubDate`) from the live `website/appcast.xml` — its zip still
   lives under the old tag. And GitHub replaces spaces in asset filenames with
   dots on upload, so the delta lands as `XQ.Lesson.Lab2-1.delta`; point the
   `sparkle:deltas` enclosure at that name, not the percent-encoded one.
4. Publish the GitHub release **before** the appcast (step 5 then step 4) —
   otherwise the feed advertises downloads that 404 until the upload lands.
   Copy the generated `appcast.xml` over `website/appcast.xml`, commit, and
   let Vercel redeploy (auto on push). The "Version X · <date>" line inside the
   landing page's download buttons reads that same file at page load, so
   this step is the only thing that keeps it current — no separate edit. (The
   values baked into `index.html` are just the no-JS fallback; refreshing them
   is optional.)
5. Publish: `gh release create v<version> release/v<version>/Lesson-Lab.dmg
   release/v<version>/*.zip release/v<version>/*.delta --title "v<version>"`.
6. Sanity check: install the **previous** DMG, open it, and confirm
   "Check for Updates…" (app menu) offers the new version.

## Model upgrades (e.g. the 4B tier)

Upload the new GGUF under a new fixed tag (`model-qwen3.5-4b`), update
`AppInfo.modelDownloadURL` / `modelSHA256` / `modelByteSize`
(`shasum -a 256`, `stat -f%z`), and ship an app release. Existing installs
keep their current model until the app asks for the new one.

## Testing the pipeline without shipping

- Download flow: `TW_MODEL_DL_TEST=1 TW_MODEL_URL=… TW_MODEL_SHA256=… TW_MODEL_DIR=…`
  (see README § probes) runs it headlessly against any server.
- Ship-small bundle: `./make-app.sh` then launch — the setup card should
  appear above the composer.
- Embedded bundle: `./make-app.sh --bundle-model` — no setup card.

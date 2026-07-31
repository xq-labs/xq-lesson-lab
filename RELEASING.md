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

### 1. Apple Developer Program (blocks everything else)
- Enroll (or join XQ's existing org account) at developer.apple.com — $99/yr.
- In Xcode or the developer portal, create a **Developer ID Application**
  certificate and install it in your keychain. Find its name with:
  `security find-identity -v -p codesigning`

### 2. Notarization credentials
```bash
xcrun notarytool store-credentials lessonlab-notary \
  --apple-id you@xqinstitute.org --team-id TEAMID \
  --password <app-specific password from appleid.apple.com>
```

### 3. Sparkle signing keys
The tools ship in Sparkle's distribution tarball (not the SPM artifact):
download `Sparkle-2.x.x.tar.xz` from github.com/sparkle-project/Sparkle/releases,
then run its `bin/generate_keys`. The **private key lands in your keychain**
(export a backup somewhere safe — losing it strands every installed app on its
current version). Put the printed **public** key in:
- the `SPARKLE_ED_PUBLIC_KEY` env var when building releases, and
- nowhere else — make-app.sh writes it into Info.plist.

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
   SIGN_IDENTITY="Developer ID Application: XQ Institute (TEAMID)" \
   NOTARY_PROFILE=lessonlab-notary \
   SPARKLE_ED_PUBLIC_KEY="<public key>" \
   scripts/make-release.sh
   ```
   Builds, signs (hardened runtime), notarizes, staples, and produces
   `release/v<version>/` with `Lesson-Lab.dmg` + `Lesson-Lab-<version>.zip`.
3. Run the `generate_appcast` command the script prints — it signs the zip
   with your private key and emits `appcast.xml` (+ `.delta` files against
   the previous release, which is what keeps updates small).
4. Copy the generated `appcast.xml` over `website/appcast.xml`, commit, and
   let Vercel redeploy (auto on push).
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

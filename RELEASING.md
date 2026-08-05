# Releasing Lesson Lab

How a build on this machine becomes a download teachers can install and that
updates itself. The moving parts:

| Piece | Where | Why |
|---|---|---|
| DMG + update zips + model | GitHub Releases (`xq-labs/xq-lesson-lab`) | Free, 2 GB/file, no bandwidth charges |
| `appcast.xml` (Sparkle feed) + landing page | Vercel (`website/`) | Stable URL the app polls for updates |
| Version numbers + URLs | `TeacherWorkspace/Sources/TeacherWorkspace/AppInfo.swift` | Single source of truth — scripts read it |

The app ships **small** (~15 MB): the 1.2 GB default model is downloaded on
first launch from a fixed-tag GitHub release (`model-qwen3.5-2b`), verified by
SHA-256, and installed under `~/Library/Application Support/LessonLab/Models/`.
Every model the app offers is one `ModelSpec` in
`TeacherWorkspace/Sources/TeacherWorkspace/ModelCatalog.swift` — URL, checksum,
size, and context length together.

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

0. Pre-flight checks (both exit non-zero on a problem):
   ```bash
   cd TeacherWorkspace
   swift build
   TW_FRAMEWORK_CHECK=1 .build/debug/TeacherWorkspace     # 5/13/37/115, no orphans
   TW_STORE=<a store.json from the previous version> TW_STORE_CHECK=1 .build/debug/TeacherWorkspace
   ```
   The second one matters whenever `PersistedState` changed: a field added
   without `?` makes the whole document fail to decode, and `load()` swallows
   that and hands the teacher an empty app.
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
5. Publish: `gh release create v<version> --repo xq-labs/xq-lesson-lab
   release/v<version>/Lesson-Lab.dmg release/v<version>/appcast/*.zip
   release/v<version>/appcast/*.delta --title "XQ Lesson Lab <version>"`.
   ⚠️ `--repo` is not optional: this checkout's `origin` is
   `xq-labs/xq-learning-workspace`, while the app downloads from — and Vercel
   deploys — `xq-labs/xq-lesson-lab`. Without it the assets land in the wrong
   repo and every URL in the appcast 404s. Push the code to both remotes.
6. Sanity check: install the **previous** DMG, open it, and confirm
   "Check for Updates…" (app menu) offers the new version.

## Adding a model

A model is one `ModelSpec` in `ModelCatalog.swift`. No upload is needed —
everything except the default streams from Hugging Face, because **GitHub
release assets are capped at 2 GB** and the 4B (2.74 GB) and 9B (5.68 GB)
both exceed it. Only the default 2B is mirrored to our own `model-qwen3.5-2b`
tag, so first launch depends on nothing but GitHub.

Hugging Face stores each file's SHA-256 as its LFS `oid`, which is exactly the
checksum the app verifies — so both `sha256` and `byteSize` come from one API
call, with nothing downloaded:

```bash
curl -s "https://huggingface.co/api/models/unsloth/<repo>/tree/main" | python3 -c "import json,sys;[print(f['path'], f['lfs']['size'], f['lfs']['oid']) for f in json.load(sys.stdin) if f['path'].endswith('.gguf')]"
```

The download URL is `https://huggingface.co/<repo>/resolve/main/<file>.gguf`
(it 302s to the HF CDN; the app follows it). Set `usesThinkPrefill` to false
for any family without a `<think>` span — Llama, for instance — or its prompt
gets a Qwen reasoning block it can't parse. Put the licence in `license`; it
shows on the card. A spec with `sha256: nil` / `available: false` renders as
"Coming soon" and can't be downloaded, which is how a model ships before its
asset is published. New domains must also go in `AppInfo.allowlistDomains`,
which the app quotes to teachers when a download fails.

## Testing the pipeline without shipping

- Download flow: `TW_MODEL_DL_TEST=1 TW_MODEL_URL=… TW_MODEL_SHA256=… TW_MODEL_DIR=…`
  (see README § probes) runs it headlessly against any server. `TW_MODEL_ID=…`
  picks a non-default catalog model; the URL/checksum overrides only apply to
  the default one.
- Ship-small bundle: `./make-app.sh` then launch — the setup card should
  appear above the composer.
- Embedded bundle: `./make-app.sh --bundle-model` — no setup card.

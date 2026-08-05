# Lesson Lab

A macOS app for teachers: an AI planning assistant that runs **entirely on-device**
(llama.cpp + Qwen GGUF). Chats, rosters, and student notes never leave the Mac.

- App code: [`TeacherWorkspace/`](TeacherWorkspace/) (Swift Package Manager, SwiftUI)
- Product roadmap: [`TeacherWorkspace/ROADMAP.md`](TeacherWorkspace/ROADMAP.md)
- Release/distribution pipeline: [`RELEASING.md`](RELEASING.md)
- Landing page (Vercel): [`website/`](website/)

## Dev setup

```bash
git clone <this repo> && cd xq-learning-workspace/TeacherWorkspace

# 1. Build the llama.cpp runtime (one time; needs cmake — brew install cmake)
scripts/setup-vendor.sh

# 2. Get the model (1.2 GB — gitignored, never committed)
#    Either copy Qwen3.5-2B-Q4_K_M.gguf from a teammate into Models/,
#    or download it from the GitHub release:
#    https://github.com/xq-labs/xq-lesson-lab/releases/download/model-qwen3.5-2b/Qwen3.5-2B-Q4_K_M.gguf

# 3. Run
swift run
```

`./make-app.sh` assembles `Lesson Lab.app` (ship-small by default — the app
downloads the model on first launch; `--bundle-model` embeds it for
offline/USB installs).

## Headless test probes

The app has env-var probes for automated verification without a GUI session —
`TW_SNAPSHOT` (window PNG capture), `TW_PROBE` (model smoke test),
`TW_MODEL_DL_TEST` (first-launch download flow), `TW_MODEL_SWITCH_TEST` and
`TW_MODEL_DELETE_TEST` (switching between and removing installed models), and
more. See the header of
[`App.swift`](TeacherWorkspace/Sources/TeacherWorkspace/App.swift).

# XQ Lesson Lab — Product Roadmap

Goal: turn the XQ Lesson Lab macOS app into a usable product for US teachers.
The app is a native SwiftUI app with an **embedded on-device model** (llama.cpp +
Qwen3.5-2B GGUF, fully offline). Key product angle: **FERPA-friendly — student
data never leaves the teacher's Mac.** The one network path for content is an
explicit, opt-in "second opinion" on a single document, gated by a deterministic
redaction check and a payload preview the teacher reads before it sends; student
work in Skill Check has no path to it at all.

## Direction (Aug 2026): the bets

The product sync of Aug 6, 2026 set XQ's direction as open infrastructure
under the systems schools already run, with **competency tools and mastery
scanners** as the product team's top priorities. This app is the working
embodiment of the two bets those come from — Mastery in Place (local-first,
school-owned, model-agnostic) and the Competency DNA layer (the framework as
something teachable and assessable, not a poster). The full mapping, the
philosophy-bar table, and the asks of the org are in `STRATEGY.md`; Phases 5
and 6 below are the build-out. Phases 1–4 stand as the record of how the app
got here.

## Current state (done)

- [x] Full UI from the claude.ai/design mock (sidebar, chat, libraries, preview panel, ⌘K search, light/dark)
- [x] Real streaming chat via embedded Qwen3.5-2B (`LlamaBackend.swift`, `vendor/llama.xcframework`)
- [x] Artifact generation: model emits ```artifact JSON blocks → parsed (`ArtifactParser.swift`, bracket-repair for small-model JSON) → clickable card in chat → stored in Rubrics/Activities/PoG libraries → preview panel
- [x] App bundle build: `make-app.sh` (bundles model + framework, ~1.2 GB)
- [x] Composer dictation (`Dictation.swift`): mic button → Apple `SFSpeechRecognizer`
   with `requiresOnDeviceRecognition = true`, en-US only. Refuses rather than
   falling back to Apple's servers, so the "nothing leaves this Mac" promise
   holds for speech too. Needs the packaged app — see the TCC note below.
- [x] Test harnesses: `TW_PROBE` (headless generation), `TW_PARSE_FILE` (parser), `TW_SNAPSHOT`/`TW_AUTOSEND`/`TW_AFTER` (GUI screenshot tests), `TW_DICTATE_FILE` (transcribe an audio file), `TW_MIC_TEST=<seconds>` (live-mic dictation, prints every phase change)

## Phase 1 — The arc that makes it a product (DONE — July 31, 2026)

- [x] **Persistence** — chats, artifacts, PoG edits, settings survive relaunch.
   JSON store in `~/Library/Application Support/TeacherWorkspace/store.json`
   (`Persistence.swift`), 1s-debounced autosave via `objectWillChange` in
   `AppState.init`. Store disabled under test env vars; `TW_STORE=<path>`
   overrides for persistence tests.
- [x] **My Classroom setup** (`ClassroomView.swift`) — teacher name/school/
   subject, class sections, student rosters + notes. Drives the system prompt
   (`AppState.systemPrompt`), sidebar groups, greeting, footer. Demo data
   (Dana Alvarez) is the editable default; any edit clears `classroom.isDemo`
   and the sample chats/artifacts step aside. "Start fresh" empties it.
   Verified: model correctly answered from a custom classroom (Sam Lee /
   Lincoln MS / Ava Torres).
- [x] **Export** (`ArtifactExport.swift`) — preview panel: Copy as Markdown,
   Save as PDF (ImageRenderer → CGContext, US-Letter width, content-sized
   single page). `TW_EXPORT_PDF=<path>` renders headlessly for tests.
   Known limit: very long artifacts render as one tall page — paginate later.
- Also fixed this session: model sometimes wraps plain answers in an
   ```artifact block with a made-up type — parser salvages the `text` field
   (`salvageText`), and the prompt now forbids non-rubric/activity/pog blocks.

## Phase 2 — Trust & data

- [x] CSV/paste roster import (July 31): `RosterImport.swift` (header-aware:
      name / first+last / notes columns; "Last, First" reversal; acronym guard)
      + `RosterImportSheet.swift` (paste or NSOpenPanel) from each class card in
      My Classroom. Test hook: `TW_ROSTER_FILE=<path>`.
- [x] Honest Plugins tab (July 31): "Available now" = Roster import (routes to
      My Classroom); everything else dimmed "SOON" cards, fake Connect toggles
      removed.
- [x] Editing artifacts (July 31): pencil/trash in preview panel for
      user-created artifacts (samples read-only); inline editors for rubric
      cells, activity steps, PoG descriptions; delete with confirmation.
      "Update the rubric" in chat replaces the existing user artifact when the
      model reuses the exact title (`AppState.store` title-match; prompt
      instructs same-title updates). Verified E2E across two runs.
- [ ] Dictation (user building, in progress): `Dictation.swift` — on-device
      SFSpeechRecognizer only (`requiresOnDeviceRecognition`), mic button with
      pulse animation, `TW_DICTATE_FILE` probe. Mic/speech usage strings are in
      make-app.sh's Info.plist.
- [ ] Google Classroom read-only import (rosters, assignments) — needs OAuth
      client / GCP project from the user
- [ ] FERPA story surfaced in UI (empty states, About): "runs privately on this
      Mac"; audit that no student data leaves the device

## Skill Check (Aug 4, 2026)

- [x] **XQ competency framework bundled** — `xq-labs/xq-competencies` v1.1.0
   vendored into `Resources/XQFramework/` (5 outcomes / 13 domains / 37
   competencies / 115 component skills, 4 progression rungs each, CC BY 4.0).
   Bundled rather than downloaded: 180KB, yearly cadence, and it keeps the
   screen working on a school network that blocks GitHub. `TW_FRAMEWORK_CHECK=1`
   asserts it parses clean.
- [x] **Skill Check screen** (`SkillCheckView.swift`) — paste/open/drop a piece
   of student work, pick a component skill, get a placement on that skill's
   progression with the student's own sentences as evidence and one sentence of
   next step. Saved, not linked to a student. Explicit save; teacher can move
   the placement.
- [x] **Staged evaluation** (`EvaluationPipeline.swift`) — five small calls per
   skill rather than one large one, reconciled in Swift. Evidence is a sentence
   *index*, so a fabricated quote isn't representable. `TW_EVAL_FILE` +
   `TW_EVAL_RUNS` reports the spread across runs and fails if a placement moves.
   This is the direct application of the standards-alignment principle below:
   curated data, model judgment only.
- [x] **Per-call generation options** (`GenerationOptions`) — greedy sampling,
   fixed seed, token ceilings, stop strings, assistant prefill. Placement was
   unreproducible without it.
- Known limits: the relevance stage is advisory (it over-accepts, so a
   mismatched skill lands at level 1 flagged rather than being refused); the
   ladder is sometimes non-monotonic and that's surfaced as "mixed evidence";
   auto-suggestion of skills is lexical only.

## Phase 3 — Teaching value

- [x] New artifact types (July 31): `quiz` (questions/choices/answers; Quizzes
      library tab; printable PDF leaves answer blanks for short-answer) and
      `email` (subject+body; lives in chat cards + ⌘K search, no tab; "review
      before sending" note). Lesson plans ride the activity schema with
      format "Lesson plan". Parser also detects **unfenced** bare artifact
      JSON (2B model sometimes skips the ``` fence — `extractBareJSON`).
- [x] Template gallery v1 (July 31): welcome screen now has 6 task cards
      (rubric, lesson, exit ticket, family email, differentiation, PoG).
- [x] Class-context picker (July 31): composer pill is a menu of classes and
      students from My Classroom; selection persisted per chat
      (`contextByChat`), threaded into the system prompt. **Pill hidden from
      the composer** since @mentions cover the same ground inline — the view
      and its plumbing are intact, re-add `contextPicker` in `ChatView` to
      bring it back.
- [x] `@mentions` in the composer (July 31): `Mentions.swift` (catalog +
      scanner) and `MentionTextView.swift` (an `NSTextView` wrapper, since
      `TextField` can't tint part of its text). Typing `@` opens a picker over
      students, classes, rubrics, activities, PoGs and quizzes; matched names
      are tinted in the field; on send each one expands into the roster note /
      rubric criteria / activity steps behind the name via `hiddenContext`, so
      the model gets the content, not a label. Mentions are re-derived from the
      text on every edit — editing a name just un-tints it, no stale chips.
      Test hooks: `TW_MENTION_TEST="<text>"`, `TW_DRAFT="<text>"`.
- [x] Sidebar sections + real folders (July 31): the flat run of
      per-class/per-student headings became two disclosure sections —
      **Folders** (always shown, with a `+`, an empty state, per-folder chat
      counts, closed by default) and **All chats** (every chat, flat).
      `SidebarSections.swift` holds the reusable `DisclosureRow` and
      `SidebarCollapseState`, which persists open/closed in `UserDefaults`
      (view state, deliberately not in the JSON store beside rosters).
      Folders are now teacher-made, not derived from My Classroom:
      `Folder` model + `AppState.folders` / `chatFolder` (chat id → folder id,
      kept off `Chat` so unpersisted sample chats can be filed too), both
      added to `PersistedState` as optionals for back-compat. Chats move by
      drag-and-drop onto a folder row (or onto ALL CHATS to unfile) and via a
      right-click "Move to" menu. Filing **moves** rather than copies: All
      chats lists `unfiledChats`, so a chat shows in exactly one place.
      Deleting a folder never deletes chats — they fall back to All chats.
      **Archive** (hover a chat row for the archive button on its trailing
      edge, or right-click → Archive) hides a chat from Folders and All
      chats and lists it under an ARCHIVED section that only appears once
      something is in it (collapsed by default). Archiving keeps `chatFolder`
      intact, so unarchiving returns the chat to its folder rather than to the
      unfiled pile; dragging an archived chat onto a folder or ALL CHATS also
      unarchives it. Archived chats still turn up in ⌘K search by design.
      The sidebar itself is resizable (drag its right edge, 200–460pt, width
      persisted as `sidebarWidth`) — the mirror of the preview panel's handle. Test hook: `TW_FOLDER_TEST=1` covers
      create/move/rename/delete plus a store round-trip.
- [x] Regenerate (July 31): button under the last reply re-runs the exchange —
      the practical mitigation for 2B quality wobbles.
- [x] Privacy surfaced (July 31): lock-shield note in the settings popover;
      demo-data hint pill on the welcome screen routes to My Classroom.
- [ ] Standards alignment: needs a *curated* NGSS dataset — deliberately not
      done via model knowledge alone (a 2B model will hallucinate standard
      codes, which is worse than no alignment for teacher trust).

- [x] Composer "+" menu (July 31): ChatGPT-style attach menu — Attach file
      (PDF via PDFKit, txt/md/csv/rtf; extracted on-device, capped at 6K chars
      for the 8K context), Reference an artifact (injects its markdown),
      Create seeds, Import roster. Attachments show as chips (composer +
      sent bubble); extracted text persists on the message (`hiddenContext`)
      so follow-ups keep the file in context. Test: `TW_ATTACH` + autosend —
      model correctly analyzed an exit-ticket CSV and cross-referenced
      roster notes.

- [x] Preview panel v2 (July 31): resizable via left-edge drag (320–900pt,
      width persisted), multi-document tabs per chat (chips with close
      buttons; per-tab scroll state), and an empty state listing the active
      chat's artifacts. Snapshot cases: `TW_PREVIEW=tabs` / `TW_PREVIEW=empty`.

## Phase 4 — Quality & distribution

- [x] Model tiering: the app carries a catalog of models (`ModelCatalog.swift`)
      instead of one hardcoded GGUF — a Models page (`TW_VIEW=models`) and a picker
      on the model line under the composer let a teacher switch, download, and
      delete models, and `LlamaBackend` reloads on the switch. Five tiers ship:
      Qwen3.5 0.8B / 2B (default) / 4B / 9B plus Llama 3.2 3B as a second opinion.
      Everything but the default streams from Hugging Face — GitHub release assets
      stop at 2 GB, which the 4B and 9B exceed. Models wanting more RAM than the
      Mac has warn but stay downloadable; `usesThinkPrefill` keeps the Qwen-only
      `<think>` prefill off other families. Probes: `TW_MODEL_SWITCH_TEST`,
      `TW_MODEL_DELETE_TEST`, `TW_MODEL_ID`
- [x] **Second opinions** — explicit, opt-in off-device review of one document
      at a time. Deliberately *not* a `ChatBackend` swap: `systemPrompt` writes
      every student name and note into turn 0, so a chat-wide cloud toggle would
      ship the roster on the next keystroke. Instead a narrower type,
      `ReviewPayload`, whose only initializer runs `RedactionGate` — a payload
      that would leak a known name cannot be constructed, and the gate runs
      again on the serialized request bytes to catch an edit made in the consent
      sheet. `PIILexicon` is built from the roster, so the check is an exact
      token list rather than a guess. The local model's only job is turning
      per-student notes into anonymous counts by returning an index into a fixed
      enum (`ClassProfile.NeedCategory`) — a name isn't representable in that
      answer, the same trick `WorkDocument` uses for quotations. BYO Anthropic
      key in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it
      never syncs to iCloud); `FrontierProvider` keeps consent, redaction, and
      audit above the transport so an XQ-hosted proxy is a later drop-in. Every
      send — and every block — is appended to `frontier-audit.jsonl`, beside
      `store.json` but never inside it. Probes: `TW_REDACT_ADVERSARIAL`,
      `TW_REVIEW_PAYLOAD`, `TW_REVIEW_BODY`, `TW_REVIEW_PARSE`,
      `TW_REVIEW_ERRORS`, `TW_REVIEW_LIVE`, `TW_AUDIT_DUMP`, plus
      `scripts/check-no-pii-leaves.sh`.
- [~] Distribution (July 31): ship-small builds (~15 MB) with first-launch
      model download (resumable, SHA-256 verified — `ModelDownload.swift`,
      `TW_MODEL_DL_TEST` probe); with no model at all the download is a
      blocking full-window gate (`ModelGateView` — chat can't work anyway),
      while future model *upgrades* use the non-blocking inline card; Sparkle 2 integrated (Check for Updates menu,
      appcast on Vercel, delta updates); make-app.sh reads version/URLs from
      AppInfo.swift, `--bundle-model` for offline installs;
      scripts/make-release.sh does sign → notarize → staple → DMG → zip;
      website/ is the Vercel landing page. REMAINING (blocked on Apple
      Developer account): Developer ID cert, notarytool profile, Sparkle keys
      — one-time setup steps in RELEASING.md; until then builds stay ad-hoc
      signed and won't open on other Macs.
- [x] First-run onboarding (July 31): 4-page welcome tour (privacy, chat →
      artifacts, libraries/preview, My Classroom setup) auto-opens once on
      first launch (`hasSeenOnboarding` in the store); reopenable via the
      header "?" button and the Help menu. Snapshot case: `TW_VIEW=onboarding`.
      Still open: a guided create-classroom wizard (tour just points at My
      Classroom for now).
- [ ] Known model-quality issue: 2B sometimes repeats level descriptions in rubrics; mitigations: retry affordance, 4B tier, prompt tuning

## Phase 4.5 — Focus cleanup (before the scanner)

A short, sharp pass that removes what a general-purpose assistant would have
and the bets don't need — full work order with file:line refs and decode-safety
notes in `CLEANUP.md`.

- [ ] Park email generation (keep rendering saved drafts — never eat teacher data)
- [ ] Re-center the welcome screen: 4 focused cards + a Skill Check card
- [ ] Plugins tab down to one honest SOON card (Google Classroom); remove the
      cosmetic Skills sub-tab
- [ ] Delete the dead class-context picker write path (superseded by @mentions;
      `contextByChat` and its store field stay)
- [ ] Retire the hardcoded PoG competency list: prompt draws from the
      framework's 5 learner outcomes, nil-safe fallback (may slide to Phase 6
      kickoff)

## Phase 5 — Mastery in Place (the scanner)

The sync's top priority, and mostly a batch composition of pieces that already
exist: `EvaluationPipeline` judges one work sample; the scanner runs it across
a set of submissions and shows the class at once.

- [ ] **Batch Skill Check** — pick an assignment name and one or more component
      skills, ingest a set of submissions, run the existing staged pipeline per
      submission on the serial backend queue with live progress ("4 of 28").
      Same intake rules as `WorkDocument` (200-char/3-sentence floor, 24K cap) —
      a scan that would produce a confident evaluation of nothing gets skipped
      and says so, per file.
- [ ] **Ingestion ladder** — folder of files first (drag a folder of
      PDFs/docx; filename → work label, never auto-matched to a roster
      student — the teacher labels the assignment, not the child, same as
      Skill Check today). Then a CSV manifest for labeled batches. Google
      Classroom read-only lands here **when the OAuth client exists** (moved
      from Phase 2 — still blocked on the org, not engineering).
- [ ] **Class mastery view** — a per-skill grid of placements where every cell
      opens the existing single-sample result card: same descriptor-beside-level
      display, same sentence-index evidence, same teacher override with the
      model's number preserved. No aggregate is shown that can't be decomposed
      into individually reviewable placements — the "understandable at every
      step" bar applies to the grid, not just the cells.
- [ ] **Batch stability probe** — extend `TW_EVAL_FILE`/`TW_EVAL_RUNS` to a
      directory: the release gate becomes "no placement in the corpus moves
      between runs," before any of it reaches a teacher.
- Student work still has no path off this Mac: scanner results, like Skill
  Check placements, are excluded from `allReviewableRefs` by construction.

## Phase 6 — Portrait decomposition (Competency DNA)

The app has two competency models that don't touch: the real XQ framework
(5/13/37/115, used by Skill Check) and the hardcoded 5-competency PoG list in
`AppState.systemPrompt`. Bet 1's decompose → implement → recompose loop is the
bridge.

- [ ] **PoG ↔ framework mapping** — a Portrait artifact's competencies gain
      optional mappings to XQ component skills. Additive and optional in
      `PersistedState` (the `Failable` pattern), so old stores and unmapped
      Portraits keep working untouched.
- [ ] **Decomposition flow** — take a school's local Portrait (typed, pasted,
      or an existing PoG artifact) and propose XQ component skills under each
      local competency. Model-suggested, teacher-confirmed per mapping — the
      same suggest-don't-decide posture as skill auto-suggestion, and every
      accepted mapping shows *why* (the skill's own description, not model
      prose).
- [ ] **Recompose evidence** — roll Skill Check / scanner placements up
      through the mapping into a local-Portrait view: "here is your Portrait,
      with the evidence behind each competency," decomposable down to
      individual placements.
- [ ] **Retire the hardcoded PoG list** — system prompt draws PoG competencies
      from the framework (or the mapped local Portrait) instead of the five
      hardcoded names. Existing PoG artifacts are untouched; only generation
      changes.
- Constraint that stands: progression rung labels and rubric levels stay
  separate vocabularies (`XQFramework.swift` warns against merging
  `levelLabels` with `SampleData.levels4` — recomposition maps evidence, it
  does not relabel rubrics).

## Architecture notes for future sessions

- `ChatBackend` protocol isolates the model; `LlamaBackend.shared` is the llama.cpp impl.
  Apple-Intelligence or another *local* backend belongs here. A **cloud** backend does
  not: `AppState.backend` is deliberately `let`, because `buildTurns` prepends
  `systemPrompt`, which interpolates every student name and note. Off-device work goes
  through `FrontierProvider`, which takes a `ReviewPayload` — a type whose only
  initializer runs the redaction gate — rather than `[ChatTurn]`, which is an array of
  unconstrained `String` and can therefore promise nothing about its contents.
- System prompt built in `AppState.systemPrompt(...)` — Phase 1.2 moves its data source from `SampleData` to the persisted Classroom model.
- Artifact contract: one fenced ```artifact JSON block per reply; schemas documented in the system prompt; parser tolerates truncated/over-closed JSON and ```json fences.
- Release builds exposed a llama.cpp pointer-lifetime bug once (dangling `llama_batch_get_one` pointer); keep pointer scopes tight in `LlamaBackend` and always smoke-test release bundles (`TW_PROBE`).
- Rebuild runtime: `vendor/llama.cpp/build-xcframework-macos.sh` (macOS-only trim of upstream script; needs cmake).
- Dictation needs the *system* Dictation switch on (System Settings → Keyboard
  → Dictation). With it off, `SFSpeechRecognizer` still reports
  `supportsOnDeviceRecognition == true` and the task starts, then fails
  immediately with `kLSRErrorDomain 201 "Siri and Dictation are disabled"` —
  which looked like the mic button flashing red and resetting. Granting the
  Microphone and Speech Recognition prompts is not enough on its own.
  `DictationController.finish(withError:)` maps that code to an actionable
  message plus an "Open Settings" deep link in the composer footer.
- Dictation and TCC: macOS blames the *responsible* process for a privacy
  request, so running the executable straight from the bundle (or `swift run`)
  attributes the mic/speech prompt to the shell, which has no usage string —
  the process is killed with `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__` rather
  than prompting. `DictationController.isLaunchedAsApp` compares
  `$__CFBundleIdentifier` to the bundle id and refuses early instead. Launch
  with `open -n "XQ Lesson Lab.app"` when testing anything mic-related.

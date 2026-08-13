# Focus cleanup — the pass before the scanner

*The work order for refocusing the app on the bets (see `STRATEGY.md`) before
Phase 5 starts. Every item carries file:line references and a decode-safety
note, because the one rule that outranks focus is: **never silently delete a
teacher's saved data.***

**Status: executed, Aug 2026** — Stages A and B landed as five commits on
`develop`; outcomes recorded per item in `ROADMAP.md` Phase 4.5. Line numbers
below describe the tree as it was when the pass was planned.

## The test

Keep what reads from or writes to the competency DNA, or protects student
data while doing so. Park what exists only because a general-purpose AI
assistant would have it.

**Keeps (untouched by this pass):** chat + My Classroom + @mentions (the
context layer), Skill Check + evaluation pipeline, the XQ framework bundle,
rubrics and quizzes (assessment objects — future skill-indexing candidates),
the whole second-opinions/redaction/audit machinery, folders/archive/
dictation/attachments (built, paid for, harmless).

## Ground rules for the deletions

- `PersistedState` decode ignores unknown JSON keys, so *removing a property*
  never throws on an old store — but the dropped data is gone on the next
  1s-debounced autosave. Acceptable for view state (skill toggles), **not**
  for content a teacher made.
- Removing an `ArtifactType` enum case doesn't corrupt a store (message refs
  decode with `try?` at `Models.swift:145-161`; frontier reviews are wrapped
  in `Failable` at `Persistence.swift:76`) — but `userEmails` itself is a
  plain array at `Persistence.swift:43`, so deleting the case + property
  would silently eat saved drafts. That's why email is **parked, not
  deleted**.
- Compiler-enforced `switch`es over `ArtifactType` (11 of them, e.g.
  `AppState.swift:588-636`, `ArtifactExport.swift:65-71`) make case removal
  loud; the silent-staleness spots are the hand-maintained lists:
  `allReviewableRefs` (`AppState.swift:499-505`), `searchGroups`
  (`AppState.swift:1083-1088`), the `TW_VIEW`/`TW_AFTER` string switches in
  `App.swift`, and the forward-compat fixture JSON
  (`Persistence.swift:134-158`).

---

## Stage A — removals (no behavior risk, ~a day)

### A1. Park the email artifact: stop generating, keep rendering

Remove every surface that *steers toward* emails; keep every path that
*renders* one, so existing drafts still open, export, and search.

Remove:
- System prompt: the email schema (`AppState.swift:1010-1011`) and `email`
  from the allowed-types closure (`AppState.swift:1015`). This alone shrinks
  the 2B model's contract — cleanup and model quality are the same workstream.
- Welcome card "family email" seed (`Models.swift:518`).
- Composer `+` → "Email to families" (`ChatView.swift:476`).
- Skills entry `family-emails` (`Models.swift:475-476`) and its default
  (`AppState.swift:56`) — subsumed by A3 anyway.
- Copy: preview empty-state "family email" (`PreviewPanel.swift:145`),
  onboarding tour mention (`OnboardingView.swift:190`).

Keep, deliberately: the `email` case and `EmailDraft` (`Models.swift:4,
81-88`), `userEmails` + persistence, `emailBody` rendering
(`PreviewPanel.swift:410-430`), export (`ArtifactExport.swift:55-57,
414-421`), search hits, `ReviewPayload` focus (`ReviewPayload.swift:54-60`),
and the parser's acceptance (`ArtifactParser.swift:94,155,237-246`) — if the
model emits one anyway, a rendered card beats a raw JSON block. Mentions
already exclude email (`Mentions.swift:16-51`); nothing to do there.

### A2. Re-center the welcome screen

- Trim `SampleData.suggestions` (`Models.swift:514-521`) from 6 cards to 4:
  keep rubric, lesson, exit ticket, PoG; drop family email (A1) and
  differentiation (generic-assistant territory).
- Add a **Skill Check card** to the welcome grid. `Suggestion` only seeds
  drafts (`ChatView.swift:72` sets `state.draft`), so this is a small
  variant in the grid at `ChatView.swift:39-43` that calls
  `state.setView(.skillCheck)` instead. Today Skill Check's only entry point
  is one sidebar row (`SidebarView.swift:106`) — for a product whose center
  is the mastery layer, it belongs on the front door.

### A3. Plugins tab: one honest card, no cosmetic toggles

- `SampleData.integrationDefs` (`Models.swift:451-458`): keep **Google
  Classroom** (the only card that maps to a bet and to Phase 5's ingestion
  ladder); delete Drive, PowerSchool, Gmail, Seesaw, Canvas (`:453-457`).
- Remove the **Skills sub-tab** entirely: tab bar
  (`LibraryViews.swift:179-202`), skills grid (`:223-284`),
  `SampleData.skillDefs` (`Models.swift:460-481`), `installedSkills`
  (`AppState.swift:54-57,198,254`; `Persistence.swift:53`). Verified: the
  install toggles are read nowhere except the card that renders them —
  promise-ware. `installedSkills` is Optional in the store, so old stores
  decode clean; losing the toggle state loses nothing real.
- Prune the unused `connections` defaults for deleted cards
  (`AppState.swift:49-52`) but keep the property — it's non-optional in
  `PersistedState` (`Persistence.swift:46`), and dictionary keys are data,
  not schema, so old stores are unaffected either way.
- "Available now" (roster import, `LibraryViews.swift:293-335`) stays as is.

### A4. Delete the dead class-context picker

Superseded by @mentions in July; verified fully dead: `contextPicker` is
declared and never referenced, and `pendingContext`'s only writer is the
picker itself.

- Delete `contextPicker` (`ChatView.swift:576-612`) and the stale
  "one-line change to put it back" comment (`ChatView.swift:303-306`).
- Delete `pendingContext` (`AppState.swift:86`), its promotion in `send()`
  (`AppState.swift:851-854`), and `composerContext` /
  `setComposerContext` (`AppState.swift:640-651`).
- **Keep** `contextByChat` — the property, its persistence
  (`Persistence.swift:48`), and the `buildTurns` read
  (`AppState.swift:945`): it still feeds the demo chats' context via the
  `SampleData.chatMeta` fallback, and keeping the field preserves any data
  an old store carries.
- Correct the two records that promise the picker can come back: the
  parenthetical in `ROADMAP.md` Phase 3 (the "re-add `contextPicker`"
  sentence) gets a dated one-line amendment, not a rewrite.

### A5. Test-hook hygiene (fold into the above commits)

- `TW_AFTER=library` cascade (`App.swift:636-647`) and `TW_STORE_CHECK`
  output (`App.swift:43-52`) — adjust only if a touched surface breaks them;
  add `emails:` to the `TW_STORE_CHECK` count line while there (it's the
  only library it doesn't print).
- Forward-compat fixture (`Persistence.swift:134-158`): leave the stale
  `installedSkills` key in the fixture JSON — that's now precisely what it
  exists to test (an old store with a key the app no longer knows).

---

## Stage B — retire the hardcoded PoG list (~a day; may slide to Phase 6 kickoff)

The one behavior change in this pass, and the one contradiction of Bet 1
inside the product: PoG generation uses five competency names hardcoded in
the system prompt (`AppState.swift:992-994,1013-1014`), a vocabulary the
bundled XQ framework doesn't contain.

- Source the PoG preamble and schema from the framework's **5 learner
  outcomes** (`XQFramework.swift`) — the portrait-grain layer — instead of
  the hardcoded names.
- Plumbing this needs (verified): `AppState` never touches `FrameworkStore`
  today; the framework loads lazily on Skill Check's `.onAppear`
  (`SkillCheckView.swift:39`). So: call `FrameworkStore.shared.loadIfNeeded()`
  at `AppState` init, and make the prompt nil-safe — fall back to the current
  hardcoded five if the framework isn't loaded yet. Both `AppState` and
  `FrameworkStore` are `@MainActor`, so the read is legal.
- **Unchanged, deliberately:** `SampleData.pogs` (`Models.swift:351-372` —
  demo-only, never persisted), existing saved PoG artifacts (only generation
  changes), the 1–5 `pogLabels` scale (`Models.swift:229`) — swapping level
  vocabularies would relabel every saved Portrait, the exact failure
  `XQFramework.swift:66-70` warns about. Full decompose/recompose stays in
  Phase 6.

---

## Verification

- Build + `TW_PROBE` smoke on a release bundle (the llama.cpp pointer rule).
- `TW_STORE_FUTURE=1` and `TW_STORE_CHECK=1` — decode degradation still
  drop-don't-die.
- **Round-trip with content**: a store containing a saved email draft loads,
  shows the draft in search and preview, and survives a save cycle intact.
- Snapshots: `TW_SNAPSHOT` welcome (4 cards + Skill Check card),
  `TW_VIEW=integrations` (one SOON card, no Skills tab),
  `TW_VIEW=skillcheck`.
- `TW_MENTION_TEST`, `TW_PARSE_FILE` unchanged-green.
- Stage B: `TW_PROBE` with a PoG request — competency names in the output
  come from the framework; with a cold `FrameworkStore`, generation still
  works via the fallback.

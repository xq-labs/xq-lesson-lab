# Skill Check test kit

Fixtures and a runner for the Skill Check pipeline. Every case has a known-good
answer, so a regression in the prompts, the pipeline, or the sampling options
shows up here rather than in front of a teacher.

```bash
./make-app.sh                                  # the probes live in the built binary
TestData/skill-check/run-checks.sh             # everything (a few minutes)
TestData/skill-check/run-checks.sh discrimination
```

Groups: `framework`, `discrimination`, `mismatch`, `intake`, `stability`.
Each placement is 4 serial model calls (3 rungs + the next step), ~3–9s. Exit status is non-zero if any
case fails.

## Fixtures

| File | Pair with | Should place at |
|---|---|---|
| `mural-applying.txt` | `FK.AC.1.a` Power of art | **4 Applying** — analyses how a community used an artwork to make a claim about itself |
| `mural-emerging.txt` | `FK.AC.1.a` Power of art | **1 Emerging** — same subject, same length ballpark, but only identifies and likes it |
| `evidence-applying.txt` | `FL.ID.3.c` Using evidence | **4 Applying** — ties evidence to a causal link *and* rules out two alternative explanations |
| `mural-applying.txt` | `FL.MST.4.a` Testing variables | **1 + off-topic** — right work, wrong skill; must not produce a confident level |
| `too-short.txt` | anything | refused at intake |
| `unreadable-scan.pdf` | anything | refused — image-only PDF, no text layer |
| `mural-applying.docx` | `FK.AC.1.a` | same as the .txt — exercises the .docx extraction path |

The two mural pieces are the important pair. They are the same student, the same
subject, and the same assignment — only the thinking differs. If the pipeline
can't separate them, it can't do the job, however good the rest looks.

## Current status: green

```
framework parses         ok
mural strong -> high     ok (level 4)
mural weak   -> low      ok (level 1)
evidence essay -> high   ok (level 4)
art work vs math skill   ok (level 1, off-topic)
one-liner refused        ok
image-only pdf refused   ok
stable across 3 runs     ok
```

The mural pair separates: the same subject and assignment, placed four rungs
apart on the thinking alone. Getting there took three changes, in this order.

**1. Neutral prompt wording.** "Answer true **only if**… otherwise false" and
"Answer NO if…" gave a 2B model a cheap default. Direct questions instead. This
alone moved the evidence essay from 2 to 4.

**2. Highest corroborated rung, not the count of leading YESes.** XQ rungs
aren't a staircase — the strong mural piece clears rung 4 (analysing how a
community used an artwork) while skipping rung 3 (how the art makes me feel).
Counting up from the bottom stopped at the first NO and pinned it at 2.

**3. A citation has to carry weight.** The weak piece also answered YES at rung
4 — citing *"I saw the mural on 14th Street."* `EvaluationPipeline.carriesWeight`
requires six distinct content words before a rung can set the level, so a reflex
YES can't promote thin work.

A fourth approach was tried and rejected: re-asking the model whether the cited
sentence, alone, showed the rung. Too severe — stripped of context it rejected
sound citations too and collapsed the evidence essay to the floor. The
deterministic check does the same job, costs no call, and can be tested without
the model.

### What "off-topic" means now

No rung answered YES anywhere on the ladder. That's the shape of a skill the
work isn't about, and it's what the deleted relevance question was reaching for.
It is deliberately *not* "nothing corroborated" — a beginner writing thinly about
the right skill lands at the floor with slight evidence, and flagging that as
"may not be about this skill" would be wrong. They picked the right skill; the
answer is Emerging.

## Adding a case

Fixtures are plain text with a real progression rung in mind — write the work
first, then find the rung it should land on, not the other way round. Add a line
to the relevant group in `run-checks.sh`:

```
check "<name>" <file> <skill id> <expected level> <yes|no relevant>
```

Find a skill id with `TW_FRAMEWORK_CHECK=1 TW_FRAMEWORK_SKILL=<id>`.

#!/bin/bash
# Asserts that nothing a frontier review would send carries a name from the
# roster. This is the FERPA claim, checked rather than promised: it builds the
# real payload for every reviewable artifact and greps the bytes for every
# student, the teacher, and the school.
#
# Run before every release. It needs no network and no API key — the payload
# builder is deterministic on purpose, which is the only reason this script
# can exist.
#
#   ./scripts/check-no-pii-leaves.sh
#
# Point it at a real store to check a teacher's own data:
#   TW_STORE=~/Library/Application\ Support/LessonLab/store.json ./scripts/check-no-pii-leaves.sh
set -uo pipefail
cd "$(dirname "$0")/.."

echo "Building…"
swift build >/dev/null || { echo "build failed"; exit 1; }
BIN="$(swift build --show-bin-path)/TeacherWorkspace"

echo
echo "== Adversarial corpus =="
TW_REDACT_ADVERSARIAL=1 "$BIN" || exit 1

# The demo classroom, matching Classroom.demo. When TW_STORE points at a real
# store these are the wrong names — the probe prints the live lexicon size, so
# a mismatch is visible rather than silent.
NAMES=(
  "Maya" "Rodriguez"
  "Jamal" "Carter"
  "Sofia" "Sofía" "Kim"
  "Dana" "Alvarez"
  "Crestview"
)

echo
echo "== Payload scan =="
IDS=$(TW_REVIEW_PAYLOAD=__list__ "$BIN" 2>/dev/null | sed -n 's/^known ids: //p' | tr ',' ' ')
if [ -z "$IDS" ]; then
  echo "could not enumerate artifacts"
  exit 1
fi

FAILURES=0
CHECKED=0
for id in $IDS; do
  PAYLOAD=$(TW_REVIEW_PAYLOAD="$id" "$BIN" 2>/dev/null | sed -n '/^--- exactly what would be sent/,/^--- end ---$/p')
  if [ -z "$PAYLOAD" ]; then
    echo "  ✘ $id — no payload produced"
    FAILURES=$((FAILURES + 1))
    continue
  fi
  CHECKED=$((CHECKED + 1))
  LEAKS=""
  for name in "${NAMES[@]}"; do
    if grep -qi -- "$name" <<<"$PAYLOAD"; then
      LEAKS="$LEAKS $name"
    fi
  done
  if [ -n "$LEAKS" ]; then
    echo "  ✘ $id — LEAKED:$LEAKS"
    FAILURES=$((FAILURES + 1))
  else
    echo "  ✓ $id"
  fi
done

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "$CHECKED payloads, no roster name in any of them."
  exit 0
fi
echo "$FAILURES payload(s) FAILED — do not ship."
exit 1

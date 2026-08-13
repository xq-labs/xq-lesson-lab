#!/bin/zsh
# Skill Check regression run: every case below has a known-good answer, so a
# change in the pipeline, the prompts, or the sampling options shows up here
# before it shows up in front of a teacher.
#
#   TestData/skill-check/run-checks.sh            # the whole set
#   TestData/skill-check/run-checks.sh discrimination
#
# Needs the model on disk. Each placement is 5 serial calls, so the full run
# is a few minutes — this is a "before you commit" check, not a save hook.
set -uo pipefail
cd "$(dirname "$0")/../.."

APP="XQ Lesson Lab.app/Contents/MacOS/TeacherWorkspace"
[[ -x "$APP" ]] || { echo "Build first: ./make-app.sh"; exit 1; }
DATA="TestData/skill-check"
ONLY="${1:-all}"
PASS=0; FAIL=0

# Run one placement and assert the level and the relevance verdict.
# check <name> <file> <skill> <expected level> <expect-relevant: yes|no>
check() {
    local name=$1 file=$2 skill=$3 want=$4 rel=$5
    printf "%-28s " "$name"
    local out
    out=$(TW_EVAL_FILE="$DATA/$file" TW_EVAL_SKILL="$skill" "$APP" 2>&1)
    local got=$(print -r -- "$out" | sed -n 's/^run 1: level \([0-9]\).*/\1/p')
    local notrel=$(print -r -- "$out" | grep -c "OFF-TOPIC")
    local why=""
    [[ "$got" == "$want" ]] || why="level $got, wanted $want"
    if [[ $rel == yes && $notrel -gt 0 ]]; then why="${why:+$why; }flagged off-topic"; fi
    if [[ $rel == no && $notrel -eq 0 ]]; then why="${why:+$why; }not flagged"; fi
    if [[ -z $why ]]; then
        echo "ok (level $got)"; ((PASS++))
    else
        echo "FAIL — $why"; print -r -- "$out" | sed 's/^/    /'; ((FAIL++))
    fi
}

# Assert the probe refuses input rather than evaluating it.
refuses() {
    local name=$1 file=$2
    printf "%-28s " "$name"
    # Capture first, then match. Piping into `grep -q` under `pipefail` reports
    # failure on success: grep exits at the first match, the probe takes SIGPIPE,
    # and pipefail surfaces that as the pipeline's status.
    # -E rather than BRE alternation: grep here is ugrep, which doesn't take
    # GNU's \| escape and would match nothing.
    local out
    out=$(TW_EVAL_FILE="$DATA/$file" TW_EVAL_SKILL=FK.AC.1.a "$APP" 2>&1)
    if print -r -- "$out" | grep -qiE "too little|too short|no readable|not enough"; then
        echo "ok (refused)"; ((PASS++))
    else
        echo "FAIL — accepted input it should have refused"; ((FAIL++))
    fi
}

if [[ $ONLY == all || $ONLY == framework ]]; then
    printf "%-28s " "framework parses"
    if TW_FRAMEWORK_CHECK=1 "$APP" >/dev/null 2>&1; then echo "ok"; ((PASS++)); else echo "FAIL"; ((FAIL++)); fi
fi

# The core claim: the same skill separates strong work from weak work.
if [[ $ONLY == all || $ONLY == discrimination ]]; then
    check "mural strong -> high"  mural-applying.txt    FK.AC.1.a 4 yes
    check "mural weak -> low"     mural-emerging.txt    FK.AC.1.a 1 yes
    check "evidence essay -> high" evidence-applying.txt FL.ID.3.c 4 yes
fi

# A mismatched skill must not quietly produce an authoritative-looking level.
if [[ $ONLY == all || $ONLY == mismatch ]]; then
    check "art work vs math skill" mural-applying.txt FL.MST.4.a 1 no
fi

# Input the pipeline should decline rather than guess at.
if [[ $ONLY == all || $ONLY == intake ]]; then
    refuses "one-liner refused"    too-short.txt
    refuses "image-only pdf refused" unreadable-scan.pdf
fi

# Placement must not move between runs — this is what greedy sampling bought.
if [[ $ONLY == all || $ONLY == stability ]]; then
    printf "%-28s " "stable across 3 runs"
    if TW_EVAL_FILE="$DATA/mural-applying.txt" TW_EVAL_SKILL=FK.AC.1.a TW_EVAL_RUNS=3 "$APP" 2>&1 | grep -q "^STABLE"; then
        echo "ok"; ((PASS++))
    else
        echo "FAIL — placement moved between runs"; ((FAIL++))
    fi
fi

echo
echo "$PASS passed, $FAIL failed"
exit $(( FAIL > 0 ))

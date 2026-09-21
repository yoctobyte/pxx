#!/bin/sh
# Refuse to publish a verdict from a run whose own inputs moved underneath it.
#
# WHY THIS IS A GUARD AND NOT A NOTE IN CLAUDE.md. The rule "do not touch the
# instrument while it is measuring" is written down, is correct, and was broken
# THREE TIMES IN ONE NIGHT (2026-09-21/22) by one seat that could quote it:
#
#   1. rebuilt compiler/pascal26 while a 1058-subject route census was running,
#      so the probe went silent partway and the census covered an unknown prefix;
#   2. edited the Makefile while `make tools-devtest` was sweeping, before the
#      sweep reached the guard that reads the Makefile;
#   3. nearly did it a third time, and stopped only because the previous two
#      were fresh enough to be embarrassing.
#
# The seat knew the rule each time. That is the finding: knowing it is not the
# mechanism. A rule that depends on everyone checking who is measuring before
# they run `make` fails the first busy evening; an abort does not.
#
# AND THE EXTENSION THAT MAKES IT RECUR: the existing rule is written about
# PUSHING during a measurement, and it lives under "push often". But FIXING does
# it too, and so does REBUILDING, and neither feels like interference because
# both feel like progress. Nobody scanning for instrument hazards looks under
# "I just fixed the thing I was measuring". That is why the check has to be
# mechanical.
#
# WHAT IT FINGERPRINTS, and why each one is here rather than being thorough:
#
#   HEAD          -- a pull, a commit or a rebase landing mid-run. Changes what
#                    the tree IS even when no file content differs.
#   tracked diff  -- an uncommitted edit to a file the run reads. This is the
#                    one that caught nobody, because `git status` stays clean
#                    for a commit and dirty for an edit, and a sweep looks at
#                    neither.
#   compiler sha  -- a rebuild. compiler/pascal26 is UNTRACKED, so no git-level
#                    check sees it move; it has to be hashed by name.
#
# USAGE
#   tools/frozen_tree_guard.sh start <tag>     # before the first job
#   tools/frozen_tree_guard.sh check <tag>     # after the last one; exit 1 if moved
#
# `check` prints CONTAMINATED and exits 1 when any of the three moved. It does
# NOT say the code is broken -- it says this run cannot be attributed to one
# tree, which is a different claim and the message says so, because a guard that
# reads as a code red gets triaged as one.
#
# A CONCURRENT PEER'S `git pull` TRIPS THIS TOO, AND THAT IS A TRUE POSITIVE,
# NOT NOISE. A sweep that straddles someone else's landing is contaminated in
# exactly the same way as one that straddles your own edit; the cost is a re-run
# and the alternative is a number nobody can attribute. If it turns out to fire
# often enough to be ignored, that is a fact about how often the tree moves
# during a six-minute sweep, and the answer is a shorter sweep -- see
# bug-t-tools-devtest-is-a-growing-sequential-sweep-behind-one-budget.
#
# POSITIVE CONTROL, because a guard that cannot fail is not a guard:
#   tools/frozen_tree_guard.sh selftest
# makes each of the three inputs move in turn, in a scratch copy, and asserts
# `check` reds on each -- and asserts it stays green when nothing moves, so the
# control cannot pass by always failing.

set -u

usage() {
    echo "usage: $0 start <tag> | check <tag> | selftest" >&2
    exit 2
}

[ $# -ge 1 ] || usage
mode=$1

state_dir=${PXX_FROZEN_GUARD_DIR:-${TMPDIR:-/tmp}/pxx-frozen-guard-$(id -u)}

# The three quantities, printed one per line. Kept in ONE function so `start`
# and `check` cannot drift apart -- two spellings of the same measurement is the
# failure this repo names most often.
fingerprint() {
    printf 'head %s\n' "$(git rev-parse HEAD 2>/dev/null || echo NO-GIT)"
    # Tracked modifications only. Untracked files are excluded deliberately: a
    # sweep writes scratch output and a temp file appearing is not the tree
    # moving. The compiler binary is untracked and is covered by its own line.
    printf 'diff %s\n' "$(git status --porcelain --untracked-files=no 2>/dev/null \
                          | sha256sum | cut -d' ' -f1)"
    if [ -f compiler/pascal26 ]; then
        printf 'cc %s\n' "$(sha256sum compiler/pascal26 | cut -d' ' -f1)"
    else
        printf 'cc %s\n' "ABSENT"
    fi
}

case "$mode" in
start)
    [ $# -eq 2 ] || usage
    mkdir -p "$state_dir" || exit 2
    fingerprint > "$state_dir/$2.fp"
    echo "frozen-tree-guard: armed for '$2' — what this run's verdict is about:"
    sed 's/^/frozen-tree-guard:   /' "$state_dir/$2.fp"
    ;;
check)
    [ $# -eq 2 ] || usage
    before="$state_dir/$2.fp"
    if [ ! -f "$before" ]; then
        # Never silently pass when the guard was not armed. An unarmed guard
        # that prints nothing is indistinguishable from a clean run, which is
        # the property the whole file exists to refuse.
        echo "frozen-tree-guard: NOT ARMED for '$2' — this says NOTHING about" >&2
        echo "frozen-tree-guard:   whether the tree moved. Call 'start' first." >&2
        exit 2
    fi
    after=$(fingerprint)
    if [ "$after" = "$(cat "$before")" ]; then
        echo "frozen-tree-guard: tree frozen for the whole run — verdict is attributable"
        exit 0
    fi
    echo "frozen-tree-guard: CONTAMINATED — this run's inputs moved while it ran." >&2
    echo "frozen-tree-guard:   This is NOT a claim that the code is broken. It is" >&2
    echo "frozen-tree-guard:   a claim that the run cannot be attributed to one" >&2
    echo "frozen-tree-guard:   tree, so neither its GREEN nor its RED may be" >&2
    echo "frozen-tree-guard:   quoted. Re-run from a settled tree." >&2
    echo "frozen-tree-guard:   what moved (before -> after):" >&2
    # diff exits 1 on difference; that is the expected path here, so do not let
    # it decide this script's status.
    diff "$before" - <<EOF >&2 || true
$after
EOF
    exit 1
    ;;
selftest)
    work=$(mktemp -d) || exit 2
    trap 'rm -rf "$work"' EXIT
    PXX_FROZEN_GUARD_DIR="$work/state"
    export PXX_FROZEN_GUARD_DIR
    fails=0

    # The NEGATIVE control first: nothing moves, check must be green. Without
    # this row the three below would pass against a guard that always reds.
    "$0" start selftest >/dev/null 2>&1
    if "$0" check selftest >/dev/null 2>&1; then
        echo "  ok   t_unmoved_tree_is_green"
    else
        echo "  FAIL t_unmoved_tree_is_green   — the guard reds on a frozen tree"
        fails=$((fails + 1))
    fi

    # Each input moved in turn, by editing the RECORDED fingerprint rather than
    # the real repo: this script must never mutate the checkout it guards, and a
    # selftest that rebuilds the compiler to prove a point is its own hazard.
    for field in head diff cc; do
        "$0" start selftest >/dev/null 2>&1
        sed -i "s/^$field .*/$field MOVED-BY-SELFTEST/" "$work/state/selftest.fp"
        if "$0" check selftest >/dev/null 2>&1; then
            echo "  FAIL t_${field}_change_is_caught   — moved and the guard passed"
            fails=$((fails + 1))
        else
            echo "  ok   t_${field}_change_is_caught"
        fi
    done

    # An unarmed check must refuse rather than pass.
    if "$0" check never-armed >/dev/null 2>&1; then
        echo "  FAIL t_unarmed_check_refuses   — passed without being armed"
        fails=$((fails + 1))
    else
        echo "  ok   t_unarmed_check_refuses"
    fi

    if [ "$fails" -gt 0 ]; then
        echo "frozen-tree-guard selftest: $fails red"
        exit 1
    fi
    echo "frozen-tree-guard selftest: 5 guard(s), 0 red"
    ;;
*)
    usage
    ;;
esac

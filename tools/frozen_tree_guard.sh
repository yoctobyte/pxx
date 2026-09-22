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
# WHAT IT DOES NOT COVER, AND THE ONLY WAY IT CAN MISLEAD YOU: ALL THREE
# FINGERPRINTS ARE PROPERTIES OF THE **LOCAL TREE**. A measurement whose
# population is a REMOTE REF is not guarded by this at all. `git log
# origin/master -1500` is a different 1500 commits after any peer pushes and
# anything fetches -- and **local HEAD need not move for that to happen**, so
# this script passes, honestly, while the thing being measured has shifted
# underneath. Correct instrument, wrong population: the failure this repo names
# most often, arriving in the tool written to prevent it.
#
# THAT IS WORSE THAN NO GUARD, because a guard that passes gets read as
# attestation for whatever it happened to be running alongside. Caught
# 2026-09-22 by frankuser, one message before a seat armed it around a census
# over `origin/master` and would have reported the green as coverage.
#
# FOR A REF-POPULATION MEASUREMENT THE REMEDY IS CHEAPER THAN A GUARD: **PIN
# THE REF.** Resolve `origin/master` to a sha ONCE, record it, and run every
# query against that sha rather than the branch name. The window is then fixed
# by construction, nothing needs arming, and the number is re-derivable by
# anyone later -- which a moving-ref count never is. Put the sha beside the
# result the way a population line goes beside the rows.
#
# Arm this as well when such a census also reads WORKING-TREE files -- ticket
# bodies, tstate/ contents, anything on disk. For a pure log/ref query it buys
# nothing.
#
# USAGE
#   tools/frozen_tree_guard.sh start <tag> [pathspec...]   # before the first job
#   tools/frozen_tree_guard.sh stop  <tag>     # the moment the LAST job ends
#   tools/frozen_tree_guard.sh check <tag>     # after the last one; exit 1 if moved
#
# With no pathspec the diff covers the whole tree: over-reports, never
# under-reports, and that is the default. With pathspecs it covers only those,
# which is how you aim it at what a run actually reads -- see the fingerprint
# function for why aiming is opt-in and why a wrong aim is the dangerous
# direction.
#
# WHY `stop` EXISTS, AND IT IS THIS SCRIPT'S OWN HAZARD ARRIVING IN THIS SCRIPT.
# Measured 2026-09-22, by the seat that wrote the file: every measurement ran on
# a provably clean tree, and `check` then printed CONTAMINATED -- because between
# the last job and the check the seat had WRITTEN THE RESULTS UP. Appending a
# section to the ticket moves the tracked diff, and the tracked diff is one of
# the three things this guard watches.
#
# So the naive lifecycle is self-defeating: recording a verdict is itself an edit,
# which means a `check` taken after the write-up ALWAYS reds, and a guard that
# always reds gets ignored -- the cry-wolf failure this repo already records for
# a born-red guard. The observer is inside the namespace it scans, which is the
# exact class the header above is about.
#
# `stop` closes the measurement window at the right instant and freezes the
# verdict, so a later `check` reports what the tree was doing WHILE THE JOBS RAN
# rather than what the author has typed since. Call it before you write anything
# down. If you forget, `check` falls back to the live comparison and its red
# means "the tree moved at some point", which is weaker but never falsely green.
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
# control cannot pass by always failing. It also covers `stop` in both
# directions, including the row that mode exists for (a write-up AFTER the
# window must not redden the verdict) and that row's own negative control
# (re-arming must clear the frozen verdict, or `stop` would be a way to switch
# the guard off permanently and every later run would pass on stale state).
#
# The three AIMING rows work differently and deliberately so: pathspec scoping
# is decided by `git status`, which no amount of editing the recorded
# fingerprint can exercise, so those rows build a SCRATCH GIT REPO and make real
# edits in and out of scope. Never the checkout this script guards. Each has its
# counterpart -- an out-of-scope edit must be ignored AND an in-scope one must be
# caught, or "aimed" would just mean "switched off" -- plus one asserting the aim
# is read back from the state file, since a `check` that re-derived it could be
# pointed elsewhere and would compare two different questions and call it green.

set -u

usage() {
    echo "usage: $0 start <tag> | stop <tag> | check <tag> | selftest" >&2
    exit 2
}

[ $# -ge 1 ] || usage
mode=$1

state_dir=${PXX_FROZEN_GUARD_DIR:-${TMPDIR:-/tmp}/pxx-frozen-guard-$(id -u)}

# The quantities, printed one per line. Kept in ONE function so `start` and
# `check` cannot drift apart -- two spellings of the same measurement is the
# failure this repo names most often. $@ is the pathspec list to scope the diff
# to; empty means the whole tree.
#
# WHY THE DIFF CAN BE AIMED, AND WHY UNAIMED IS STILL THE DEFAULT. Measured
# 2026-09-22: a `full` tier was in flight while its operator committed a
# docs-only correction, and the unaimed guard reds -- correctly about the TREE
# and uselessly about the RUN, whose jobs read test/**, lib/** and a compiler
# binary snapshotted at start. That is a guard crying wolf on a run whose real
# inputs were frozen, and this repo already records what that teaches: a guard
# that reds when it is used correctly gets ignored.
#
# So `start <tag> [pathspec...]` scopes the diff to what the run actually reads,
# which is the "a guard must be AIMED" rule applied to this guard. The pathspec
# list is RECORDED IN THE STATE FILE and read back by `check`/`stop`, so the two
# ends cannot be aimed differently -- an aimed guard whose aim drifts between
# start and check would be the worse bug.
#
# UNAIMED REMAINS THE DEFAULT ON PURPOSE. Passing no pathspec watches everything,
# which over-reports and never under-reports. Aiming is an assertion about what
# a run reads, and a WRONG aim fails silent -- the direction this file exists to
# refuse. Aim only when you can name the inputs; if you are guessing, do not.
fingerprint() {
    # THIS SCRIPT'S OWN HASH, FIRST LINE, AND IT IS HERE FOR A MEASURED REASON.
    # 2026-09-22: a `full` tier was armed, and while it ran the author added the
    # `paths` line below. `start` and `check` therefore used DIFFERENT fingerprint
    # FORMATS, so part of the resulting diff was an edit to the instrument rather
    # than movement in the tree -- and the reader had to infer that from noise in
    # a diff. Third instrument-touch of that night and the SECOND inside the tool
    # written to prevent it, by the seat who wrote both the tool and the header.
    #
    # That is structural, not careless: the person maintaining a guard is the
    # person using it, so the only defence that survives is one the guard
    # performs ON ITSELF. Now the condition is NAMED -- `check` says
    # INSTRUMENT CHANGED WHILE ARMED instead of leaving it to be spotted.
    printf 'tool %s\n' "$(sha256sum "$0" 2>/dev/null | cut -d' ' -f1)"
    printf 'head %s\n' "$(git rev-parse HEAD 2>/dev/null || echo NO-GIT)"
    # The aim is part of the fingerprint, so a start and a check with different
    # pathspecs mismatch loudly instead of comparing two different questions.
    printf 'paths %s\n' "${*:-ALL}"
    # Tracked modifications only. Untracked files are excluded deliberately: a
    # sweep writes scratch output and a temp file appearing is not the tree
    # moving. The compiler binary is untracked and is covered by its own line.
    printf 'diff %s\n' "$(git status --porcelain --untracked-files=no -- "$@" 2>/dev/null \
                          | sha256sum | cut -d' ' -f1)"
    if [ -f compiler/pascal26 ]; then
        printf 'cc %s\n' "$(sha256sum compiler/pascal26 | cut -d' ' -f1)"
    else
        printf 'cc %s\n' "ABSENT"
    fi
}

# Re-read the aim recorded by `start`, so `check` and `stop` ask the same
# question `start` did rather than whatever the caller remembers.
recorded_paths() {
    p=$(sed -n 's/^paths //p' "$1")
    [ "$p" = "ALL" ] && p=""
    echo "$p"
}

case "$mode" in
start)
    [ $# -ge 2 ] || usage
    mkdir -p "$state_dir" || exit 2
    # Clear any frozen verdict from a PREVIOUS run under this tag. Without this
    # a re-armed tag would inherit the old run's `closed` marker and `check`
    # would report attributable without having compared anything -- a guard
    # passing on stale state, which is the one outcome worse than a false red.
    rm -f "$state_dir/$2.closed"
    tag=$2
    shift 2
    fingerprint "$@" > "$state_dir/$tag.fp"
    echo "frozen-tree-guard: armed for '$tag' — what this run's verdict is about:"
    sed 's/^/frozen-tree-guard:   /' "$state_dir/$tag.fp"
    if [ $# -gt 0 ]; then
        echo "frozen-tree-guard:   AIMED: the diff above covers only those paths."
        echo "frozen-tree-guard:   A change anywhere else will NOT red this run."
    fi
    ;;
stop)
    [ $# -eq 2 ] || usage
    before="$state_dir/$2.fp"
    if [ ! -f "$before" ]; then
        echo "frozen-tree-guard: NOT ARMED for '$2' — nothing to close." >&2
        exit 2
    fi
    if [ "$(fingerprint $(recorded_paths "$before"))" = "$(cat "$before")" ]; then
        # Freeze the verdict. A later `check` reads this rather than re-comparing
        # against a tree the author has since written the results into.
        : > "$state_dir/$2.closed"
        echo "frozen-tree-guard: measurement window CLOSED for '$2' — tree was frozen"
        echo "frozen-tree-guard:   throughout. Write-ups from here cannot affect the verdict."
        exit 0
    fi
    echo "frozen-tree-guard: CONTAMINATED — inputs moved before the window closed." >&2
    echo "frozen-tree-guard:   Not a claim the code is broken; a claim this run" >&2
    echo "frozen-tree-guard:   cannot be attributed to one tree. Re-run settled." >&2
    diff "$before" - <<EOF >&2 || true
$(fingerprint $(recorded_paths "$before"))
EOF
    exit 1
    ;;
check)
    [ $# -eq 2 ] || usage
    before="$state_dir/$2.fp"
    if [ -f "$state_dir/$2.closed" ]; then
        echo "frozen-tree-guard: window was closed by 'stop' — verdict attributable"
        echo "frozen-tree-guard:   (edits made after the window are deliberately ignored)"
        exit 0
    fi
    if [ ! -f "$before" ]; then
        # Never silently pass when the guard was not armed. An unarmed guard
        # that prints nothing is indistinguishable from a clean run, which is
        # the property the whole file exists to refuse.
        echo "frozen-tree-guard: NOT ARMED for '$2' — this says NOTHING about" >&2
        echo "frozen-tree-guard:   whether the tree moved. Call 'start' first." >&2
        exit 2
    fi
    after=$(fingerprint $(recorded_paths "$before"))
    if [ "$after" = "$(cat "$before")" ]; then
        echo "frozen-tree-guard: tree frozen for the whole run — verdict is attributable"
        exit 0
    fi
    # Name this one specifically. A changed instrument means the two fingerprints
    # may not even be comparable, which is a different and worse condition than
    # the tree having moved -- and it is invisible unless said out loud.
    if [ "$(sed -n 's/^tool //p' "$before")" != "$(sha256sum "$0" | cut -d' ' -f1)" ]; then
        echo "frozen-tree-guard: INSTRUMENT CHANGED WHILE ARMED — $0 itself was" >&2
        echo "frozen-tree-guard:   edited between 'start' and now, so the two" >&2
        echo "frozen-tree-guard:   fingerprints may not be comparable at all. This" >&2
        echo "frozen-tree-guard:   says NOTHING about the tree or the code. Re-arm" >&2
        echo "frozen-tree-guard:   and re-run; do not interpret the diff below." >&2
        exit 1
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

    # `stop` on a frozen tree closes the window.
    "$0" start selftest >/dev/null 2>&1
    if "$0" stop selftest >/dev/null 2>&1; then
        echo "  ok   t_stop_closes_a_frozen_window"
    else
        echo "  FAIL t_stop_closes_a_frozen_window   — reds on a frozen tree"
        fails=$((fails + 1))
    fi

    # THE ROW THIS MODE EXISTS FOR: after `stop`, an edit (the write-up) must
    # NOT turn the verdict red. Simulated by moving the recorded fingerprint,
    # which is what a real edit does to the comparison.
    sed -i 's/^diff .*/diff MOVED-BY-WRITEUP/' "$work/state/selftest.fp"
    if "$0" check selftest >/dev/null 2>&1; then
        echo "  ok   t_writeup_after_stop_is_not_contamination"
    else
        echo "  FAIL t_writeup_after_stop_is_not_contamination   — write-up reddened it"
        fails=$((fails + 1))
    fi

    # ...and the negative control for that row, or it would pass against a
    # `stop` that simply disables the guard forever: re-arming must CLEAR the
    # frozen verdict, so a moved tree reds again under the same tag.
    "$0" start selftest >/dev/null 2>&1
    sed -i 's/^cc .*/cc MOVED-AFTER-REARM/' "$work/state/selftest.fp"
    if "$0" check selftest >/dev/null 2>&1; then
        echo "  FAIL t_rearm_clears_the_frozen_verdict   — stale 'closed' still passing"
        fails=$((fails + 1))
    else
        echo "  ok   t_rearm_clears_the_frozen_verdict"
    fi

    # An edited INSTRUMENT must be named, not left as noise in a diff.
    "$0" start selftest >/dev/null 2>&1
    sed -i 's/^tool .*/tool EDITED-WHILE-ARMED/' "$work/state/selftest.fp"
    if "$0" check selftest 2>&1 | grep -q "INSTRUMENT CHANGED WHILE ARMED"; then
        echo "  ok   t_edited_instrument_is_named_not_inferred"
    else
        echo "  FAIL t_edited_instrument_is_named_not_inferred   — reported as a plain tree move"
        fails=$((fails + 1))
    fi

    # ...and its negative control: an unedited instrument must NOT claim it
    # changed, or every ordinary contamination would be misreported as this.
    "$0" start selftest >/dev/null 2>&1
    sed -i 's/^head .*/head MOVED/' "$work/state/selftest.fp"
    if "$0" check selftest 2>&1 | grep -q "INSTRUMENT CHANGED WHILE ARMED"; then
        echo "  FAIL t_unedited_instrument_is_not_blamed   — blamed the tool for a tree move"
        fails=$((fails + 1))
    else
        echo "  ok   t_unedited_instrument_is_not_blamed"
    fi

    # `stop` must red on a tree that moved during the window.
    "$0" start selftest >/dev/null 2>&1
    sed -i 's/^head .*/head MOVED-DURING-RUN/' "$work/state/selftest.fp"
    if "$0" stop selftest >/dev/null 2>&1; then
        echo "  FAIL t_stop_reds_on_a_moved_tree   — closed a contaminated window"
        fails=$((fails + 1))
    else
        echo "  ok   t_stop_reds_on_a_moved_tree"
    fi

    # THE AIMING ROWS NEED A REAL REPO AND REAL EDITS. The rows above move the
    # RECORDED fingerprint, which cannot test a pathspec -- scoping is decided by
    # `git status`, so proving it needs files that actually change. A scratch
    # repo, never the checkout this script guards.
    self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
    repo="$work/repo"
    mkdir -p "$repo/watched" "$repo/elsewhere"
    (
        cd "$repo" || exit 1
        git init -q . 2>/dev/null
        git config user.email s@s; git config user.name s
        echo one > watched/f; echo one > elsewhere/g
        git add -A; git commit -qm init
    ) >/dev/null 2>&1

    # An edit OUTSIDE the aim must not red an aimed run.
    ( cd "$repo" && "$self" start aimed watched >/dev/null 2>&1 \
        && echo changed > elsewhere/g \
        && "$self" check aimed >/dev/null 2>&1 )
    if [ $? -eq 0 ]; then
        echo "  ok   t_aimed_guard_ignores_an_out_of_scope_edit"
    else
        echo "  FAIL t_aimed_guard_ignores_an_out_of_scope_edit   — red on a path it was not aimed at"
        fails=$((fails + 1))
    fi

    # ...and its negative control, or the row above would pass against an aim
    # that simply disables the diff check: an edit INSIDE the aim must red.
    ( cd "$repo" && "$self" start aimed watched >/dev/null 2>&1 \
        && echo changed > watched/f \
        && "$self" check aimed >/dev/null 2>&1 )
    if [ $? -ne 0 ]; then
        echo "  ok   t_aimed_guard_catches_an_in_scope_edit"
    else
        echo "  FAIL t_aimed_guard_catches_an_in_scope_edit   — missed a watched path"
        fails=$((fails + 1))
    fi

    # The aim must come from the STATE FILE, not from the caller's memory. A
    # `check` that re-derived the aim could be pointed somewhere else and would
    # then compare two different questions and call it green.
    ( cd "$repo" && git checkout -q HEAD -- . \
        && "$self" start aimed watched >/dev/null 2>&1 \
        && grep -q '^paths watched$' "$work/state/aimed.fp" )
    if [ $? -eq 0 ]; then
        echo "  ok   t_aim_is_recorded_in_the_state_file"
    else
        echo "  FAIL t_aim_is_recorded_in_the_state_file   — check could drift from start"
        fails=$((fails + 1))
    fi

    if [ "$fails" -gt 0 ]; then
        echo "frozen-tree-guard selftest: $fails red"
        exit 1
    fi
    echo "frozen-tree-guard selftest: 14 guard(s), 0 red"
    ;;
*)
    usage
    ;;
esac

#!/bin/sh
# sync.sh — land your commits on your branch's upstream without hand-resolving
# the board.
#
# BRANCH-AWARE since the dev-branch workflow (2026-08-25): this syncs whatever
# branch you are ON against origin/<that branch>, rather than hardcoding master.
# Workers live on `dev`; master is a stable snapshot that the coordinator
# advances by MERGE, once or twice a day. Never run this to move master --
# `git merge --no-ff dev` is that job, because a rebase would rewrite the shas
# that tstate verdicts and the board's resolve citations are keyed by.
#
# Why this exists: BOARD.md is GENERATED, so any two agents that both touched
# tickets conflict on it every single time (four times in one afternoon on
# 2026-07-31). The resolution is always identical and always mechanical —
# discard both sides, regenerate from the tickets, continue. Doing that by hand
# is pure tax, and doing it wrong (merging the two halves) produces a board that
# matches neither box.
#
# Also fixes the quieter one: a background `git fetch` racing a foreground
# `git pull` corrupts FETCH_HEAD and yields "Cannot rebase onto multiple
# branches". We always fetch with an explicit refspec and never rely on
# FETCH_HEAD.
#
# Usage:
#   tools/sync.sh            # pull --rebase (auto-resolving BOARD.md), then push
#   tools/sync.sh --no-push  # just get current; leave pushing to the caller
#
# Safe to run with nothing to push. Exits non-zero if a conflict it does NOT
# know how to resolve needs a human — it never guesses at real content.
set -eu

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# The branch we are on IS the branch we sync. Resolved once, up front: a
# detached HEAD or a mid-rebase state would otherwise silently retarget us.
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "HEAD" ]; then
    echo "sync: detached HEAD -- check out a branch first" >&2
    exit 1
fi

# EVERY generated board file, not just BOARD.md. `board-md` also writes
# BOARD-brief.md and BOARD-done.md (done/ alone was 190KB of BOARD.md, so the
# archived tables were split out) — and the moment a second generated file
# existed, sync.sh stopped being able to finish a rebase: it auto-resolved
# BOARD.md, then refused at BOARD-brief.md and handed a mechanical conflict to
# a human. The pattern must match whatever board-md emits, so it is a glob.
BOARD_GLOB='devdocs/progress/BOARD*.md'

# The raw placeholder, for verify_citations_landed's literal search. Duplicating
# the STRING from progress.py is deliberate and is not the drift this file has
# been burned by twice: what drifted was two independent MATCHERS, and the whole
# point of that guard is to not share a matcher. A constant that both sides spell
# the same way is not an assumption; a regex that one side widens is.
PLACEHOLDER='PENDING-COMMIT'
PUSH=1
[ "${1:-}" = "--no-push" ] && PUSH=0

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "sync: working tree is dirty — commit or stash first" >&2
    git status --short | head -10 >&2
    exit 1
fi

# A rebase leaves one of these two directories behind for its whole duration.
# `git status` says so in prose; this is the same fact in a form a script can
# branch on, and the branch matters -- see the note in the conflict loop.
rebase_in_progress() {
    d=$(git rev-parse --git-path rebase-merge 2>/dev/null)
    [ -d "$d" ] && return 0
    d=$(git rev-parse --git-path rebase-apply 2>/dev/null)
    [ -d "$d" ]
}

# Regenerating the boards is a pure function of the ticket files, and it is not
# cheap: 18-21s measured on plexus 2026-08-30, ~5s of it the markdown and the
# rest BOARD.html. Every one of those seconds is spent INSIDE the fetch->push
# window — which is what makes the NEXT race likely, so sync.sh was widening its
# own window on every retry, and the retries are what the window causes.
#
# So skip the regeneration when the tickets have not moved since the last one.
# The fingerprint covers everything under devdocs/progress EXCEPT the generated
# boards themselves and tstate/: the watcher publishes tstate every few minutes
# and tstate is NOT a ticket status (progress.py's STATUSES), so tstate churn
# cannot change a board. That one exclusion is what makes the skip fire during
# exactly the contention the retries exist for — the daemon is the busiest
# writer on the tree and none of its writes mean anything to the board.
#
# The bias is deliberate. A directory this covers but the board ignores costs
# only a needless regeneration; one it MISSES would commit a stale board. So it
# covers everything and names its two exceptions rather than listing STATUSES,
# which would go stale the day a status is added.
TICKETS_FINGERPRINT=''
ticket_fingerprint() {
    git ls-tree -r HEAD -- devdocs/progress 2>/dev/null \
        | grep -v -e 'devdocs/progress/tstate/' \
                  -e 'devdocs/progress/BOARD[^/]*$' \
        | sha1sum | cut -d' ' -f1
}

rebase_onto_origin() {
    git fetch --no-write-fetch-head -q origin "$BRANCH"

    if ! git rebase -q "origin/$BRANCH" 2>/dev/null; then
        # Only the GENERATED board files may be auto-resolved. Anything else is
        # real content and belongs to a human.
        while true; do
            conflicted=$(git diff --name-only --diff-filter=U)
            [ -z "$conflicted" ] && break
            others=$(printf '%s\n' "$conflicted" \
                     | grep -v '^devdocs/progress/BOARD.*\.md$' || true)
            if [ -n "$others" ]; then
                echo "sync: conflicts I will not guess at:" >&2
                printf '  %s\n' $others >&2
                echo "sync: resolve them, then: git rebase --continue" >&2
                exit 1
            fi
            # Generated boards only — discard both sides, regenerate from the
            # tickets. The resolution is always identical and always mechanical.
            git checkout --ours -- $BOARD_GLOB 2>/dev/null || true
            # --no-html: BOARD.html is gitignored, is never staged here, and is
            # ~87% of board-md's runtime. Nothing in a rebase wants it.
            tools/progress.sh board-md --no-html >/dev/null 2>&1 || true
            git add $BOARD_GLOB
            if ! GIT_EDITOR=true git rebase --continue >/dev/null 2>&1; then
                if [ -z "$(git diff --name-only --diff-filter=U)" ]; then
                    # No unmerged paths and --continue still refused. TWO very
                    # different states look identical here and conflating them
                    # is how a commit was silently lost on 2026-08-30:
                    #
                    #   (a) the rebase FINISHED. Nothing to do.
                    #   (b) the commit became EMPTY -- every change it carried
                    #       was a generated board file and --ours took the other
                    #       side -- so git wants `--skip` and the rebase is STILL
                    #       IN PROGRESS.
                    #
                    # Breaking out on (b) drops us to the amend below WHILE
                    # REBASING, which rewrites the last APPLIED commit and folds
                    # the pending one into it. Exit 0, clean tree, successful
                    # push, and the only tell is a git log one commit shorter
                    # than expected -- which nobody checks after a push that
                    # worked. Two commits landed as one under the first message;
                    # the code survived, the second message, its measurements
                    # and its `resolves:` line did not.
                    if rebase_in_progress; then
                        git rebase --skip >/dev/null 2>&1 || {
                            echo "sync: rebase is stuck and I will not guess" >&2
                            echo "sync: resolve it, then: git rebase --continue" >&2
                            exit 1
                        }
                        continue
                    fi
                    break      # (a) genuinely finished
                fi
            fi
        done
    fi

    # The boards can also be merely stale after a clean rebase — regenerate and
    # fold them into the top commit rather than leaving a dangling diff.
    #
    # NEVER while a rebase is in progress: HEAD is then a partially-replayed
    # commit, not yours, and amending it destroys the boundary between two of
    # your commits. See the note above -- this is the second half of that fix,
    # and it is the half that holds even if some future path reaches here
    # mid-rebase by a route nobody anticipated.
    if rebase_in_progress; then
        echo "sync: still mid-rebase after resolution — refusing to amend" >&2
        echo "sync: this would fold two of your commits into one; run:" >&2
        echo "sync:   git status   # then finish or abort the rebase by hand" >&2
        exit 1
    fi
    fp=$(ticket_fingerprint)
    if [ "$fp" != "$TICKETS_FINGERPRINT" ]; then
        tools/progress.sh board-md --no-html >/dev/null 2>&1 || true
        # Set it AFTER the regeneration, so an interrupted or failed run does
        # not record a fingerprint whose board was never written.
        TICKETS_FINGERPRINT=$fp
        if [ -n "$(git status --porcelain -- $BOARD_GLOB)" ]; then
            git add $BOARD_GLOB
            git commit -q --amend --no-edit
        fi
    fi
}

# Push, re-rebasing on a race. The daemon publishes tstate every few minutes,
# so origin can move between our fetch and our push — a plain `push` then fails
# with "fetch first" and the caller has to run sync.sh again by hand (observed
# 2026-08-03 landing the ticket below). Rebase and retry is exactly what that
# rerun does, minus the human.
# SYNC_PUSH_TRIES: 3 was too few once the fleet grew. On 2026-08-29, with nine
# writers live and the watcher publishing tstate continuously, this exhausted its
# budget TWICE IN A ROW on one resolve — and a tight fetch/rebase/push loop landed
# it first try immediately after, so it was retry budget, not a real conflict.
# Raised 6 -> 12 on 2026-08-30: the budget was exhausted for real tonight,
# with eight lanes pushing and the watcher publishing tstate continuously.
# The retries are cheap (fetch + rebase of generated boards) and the cost of
# running out is a hand re-run, so the budget should be set by how busy the
# tree gets rather than by how busy it usually is.
SYNC_PUSH_TRIES="${SYNC_PUSH_TRIES:-12}"

# Milliseconds of entropy per call. /dev/urandom is the source; $$ is the
# fallback and is deliberately POOR — it is constant within a process, so if the
# device is ever unreadable the backoff degrades to the deterministic behaviour
# we are replacing rather than to something that looks random and is not.
jittered_backoff() {
    _t=$1
    _r=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')
    [ -n "$_r" ] || _r=$$
    _ms=$(( _t * 500 + _r % (_t * 1000 + 1) ))
    printf '%d.%03d\n' "$(( _ms / 1000 ))" "$(( _ms % 1000 ))"
}

push_with_retry() {
    tries=0
    while [ "$tries" -lt "$SYNC_PUSH_TRIES" ]; do
        if git push -q origin "$BRANCH" 2>/dev/null; then
            return 0
        fi
        tries=$((tries + 1))
        echo "sync: push raced another writer — rebasing and retrying ($tries/$SYNC_PUSH_TRIES)" >&2
        # Brief, growing, RANDOMISED pause. The growth was here from the start
        # and the comment always said it exists to break lockstep — but the
        # delay was `sleep "$tries"`, identical in every process, which is the
        # one thing that cannot break lockstep. Two writers that collide at t=0
        # both sleep exactly 1s, both retry at t=1, and stay in phase for the
        # whole budget; the fleet grew to nine writers and the budget started
        # running out (2026-08-29, 2026-08-30) with no single slow pusher to
        # blame. Jitter is the fix, and it is the fix precisely because it is
        # the property the old line lacked, not because it is longer.
        #
        # Uniform over [tries/2, 3*tries/2), so the MEAN is unchanged at
        # `tries` and the total budget is the same as before — this trades no
        # patience for decorrelation.
        sleep "$(jittered_backoff "$tries")"
        rebase_onto_origin
    done
    git push origin "$BRANCH"       # let the real error out (non-zero propagates)
}

# Fail loudly. push_with_retry already returned the real status; what was missing
# was anyone LOOKING at it. The old caller was:
#
#     push_with_retry
#     echo "sync: pushed — ..."
#
# so the failing status was replaced by the echo's, sync.sh exited 0, and the
# commit sat unpushed while the resolve line still read PENDING-COMMIT. Found by
# frankD 2026-08-29, who caught it only because it verified with
# `git merge-base --is-ancestor` instead of trusting the exit code.
#
# This is the same shape as the gate.sh confusion the same evening: ANY trailing
# command replaces the status — `| tail`, `; echo`, `&& cp`, a cleanup line. Here
# it was inside the tool rather than at a call site, which is worse: every caller
# inherited it and none could see it.
push_or_die() {
    if push_with_retry; then
        return 0
    fi
    echo "sync: PUSH FAILED after $SYNC_PUSH_TRIES attempts — YOUR WORK IS NOT ON ORIGIN." >&2
    echo "sync: the commit is local only; Track T cannot see it and no ticket citation is" >&2
    echo "sync: valid yet. Re-run tools/sync.sh, or raise SYNC_PUSH_TRIES." >&2
    exit 1
}

# Fill in the commit citation of every ticket resolved without one.
#
# `progress.sh resolve <slug>` writes PENDING-COMMIT rather than a sha, because
# the only sha available at resolve time is the PRE-rebase one and this repo
# rebases on nearly every sync (the watcher daemon publishes tstate every few
# minutes). Cited shas were therefore rewritten out of existence the moment
# they were pushed — four in one session, none of them lookupable from the
# other box (bug-t-resolve-cites-a-sha-the-rebase-then-rewrites).
#
# Called AFTER the push, so the resolve commit is on origin and its sha is now
# final. The fill commit itself may still be rebased by a later push — that is
# harmless, since it cites shas that already landed, never its own.
fill_pending_commits() {
    # Every BUCKET, not just done/ + decided/: a resolved ticket can be filed
    # onward the same commit (done-followup/ when it spawned a follow-up, which
    # is what the first ticket resolved through this path did), and a
    # placeholder left in any bucket is a citation nobody can look up.
    #
    # The `*/*.md` glob is load-bearing: it keeps the board's own docs
    # (devdocs/progress/README.md, which DOCUMENTS the placeholder by name, and
    # BOARD.md) out of reach. Widening this to the whole directory rewrote the
    # README's prose into a sha on 2026-08-03.
    # ONE definition of "owes a citation", and it lives in progress.py. This
    # used to be a grep literal here and a substring test there; the two drifted
    # apart and neither tool could see the other disagreeing, so `check` reported
    # 17 forever while this function filled nothing
    # (bug-t-sync-fills-one-spelling-of-pending-commit-and-check-counts-two).
    # `pending` prints "<path>\t<sha>" per ticket, sha empty if undeterminable.
    pending=$(python3 "$(dirname "$0")/progress.py" pending 2>/dev/null || true)
    [ -n "$pending" ] || return 0

    filled=""
    while IFS="$(printf '\t')" read -r f sha; do
        [ -n "$f" ] || continue
        if [ -z "$sha" ]; then
            echo "sync: $f owes a citation but its resolve commit could not be determined — left alone" >&2
            continue
        fi
        # BOTH live spellings: the frontmatter field workers write by hand, and
        # the Log line `resolve` writes. Filling one and counting two is the bug.
        # Anchored to line start for the same reason progress.py's PENDING_RE is
        # — a ticket that QUOTES the placeholder mid-line is prose, not a
        # citation, and this bug's own ticket does exactly that.
        # ONE IMPLEMENTATION, not just one definition. This used to be a pair
        # of sed literals covering two of the placeholder's spellings while
        # progress.py's PENDING_RE knew about more — so `check` could report
        # tickets this loop was structurally unable to fill, which is the exact
        # shape of the bug that pair of literals was written to fix. Two more
        # spellings turned up on 2026-08-29 (`resolved: PENDING-COMMIT`, and a
        # Log line ENDING in it with no `commit` keyword) and both tools were
        # blind to both. Substitution now lives beside detection.
        python3 "$(dirname "$0")/progress.py" fill "$f" "$sha"
        git add "$f"
        filled="$filled $f"
    done <<EOF
$pending
EOF
    [ -n "$filled" ] || return 0

    git commit -q -m "docs(progress): record the shas the resolves landed as

$(printf '%s\n' $filled)"
    rebase_onto_origin
    push_or_die
    echo "sync: filled PENDING-COMMIT —$filled"
}

# ---------------------------------------------------------------------------
# THE MANIFEST. Captured BEFORE the first rebase, because the rebase is what
# loses things.
#
# On 2026-08-30 sync.sh DROPPED an entire commit: four consecutive
# rebase(start)/rebase(finish) pairs each landed on origin's tip and never
# replayed the local commit, leaving the branch pointing at origin. Then it
# pushed SOMEBODY ELSE'S commit and printed "sync: pushed — <their subject>".
# `git rev-list --count origin/master..HEAD` said 0, exit code 0, tree clean.
# Every single signal said pushed. The work existed only in the reflog.
#
# That was the second loss in two hours from the same tool -- the first folded
# two commits into one -- and both were caught by the SAME check, run by hand:
# name what you expect to land, then look for it on origin AFTER the push, BY
# CONTENT. Checking by sha manufactures false alarms, because an ordinary
# rebase rewrites every sha; checking the exit code, the ahead-count or the
# tree state catches neither loss, since all three are exactly what a healthy
# push leaves behind.
#
# So the check moves into the tool. A guard that has to be remembered is a
# guard for the two hours after someone is burned by it.
# .gitattributes routes devdocs/progress/BOARD*.md to the `ours` merge driver,
# but a driver is git CONFIG and config is not committable -- so the attribute is
# silently inert in any clone where nobody ran this by hand. It sat inert from the
# day it was written. Register it here: a clone that has ever synced is covered.
git config merge.ours.driver true 2>/dev/null || true

# A FOLLOWABLE "is it safe to touch the tree yet" SIGNAL. `pgrep -f tools/sync.sh`
# matches its own command line and the [s]ync bracket trick matches any compound
# command that merely CONTAINS the string, so a peer asking "is sync running?" got
# yes forever and waited on nothing -- three times in one night, by someone who
# knew the trap. A file has no such ambiguity:
#     [ -e .git/sync-running ] && echo busy
SYNC_LOCK="$(git rev-parse --git-dir)/sync-running"
printf '%s pid=%s\n' "$(date -Is)" "$$" > "$SYNC_LOCK" 2>/dev/null || true
trap 'rm -f "$SYNC_LOCK" 2>/dev/null' EXIT

manifest=$(git log --format=%s "origin/$BRANCH..HEAD" 2>/dev/null)
manifest_n=$(printf '%s' "$manifest" | grep -c . || true)

# The TICKET files our commits touch, captured at the same moment and for the
# same reason: the rebase rewrites shas, so ask the question while the range
# still means what we think it means. Same `*/*.md` glob fill_pending_commits
# uses -- it keeps README.md (which documents the placeholder by name) and the
# generated boards out of reach, and that glob is load-bearing there for exactly
# the reason it is load-bearing here.
manifest_tickets=$(git log --format= --name-only "origin/$BRANCH..HEAD" \
                   -- 'devdocs/progress/*/*.md' 2>/dev/null | sort -u)

# ...and, separately, the tickets this run RESOLVED -- newly added to a resolved
# bucket. Not the same set: appending a correction to a ticket resolved last week
# touches it without resolving it, and a nudge that fired on that would be noise
# on every write-up. `--no-renames` is deliberate: a `git mv` from backlog/ to
# done/ is otherwise reported as R and --diff-filter=A would never see the very
# move this is about.
manifest_resolved=$(git log --no-renames --diff-filter=A --format= --name-only \
                    "origin/$BRANCH..HEAD" \
                    -- 'devdocs/progress/done/*.md' \
                       'devdocs/progress/decided/*.md' \
                       'devdocs/progress/done-followup/*.md' 2>/dev/null | sort -u)

# Did every commit we set out to push actually arrive? Subject match against
# origin, which survives the sha rewriting that a rebase does by design.
verify_manifest_landed() {
    [ "$manifest_n" -gt 0 ] || return 0
    git fetch --no-write-fetch-head -q origin "$BRANCH" 2>/dev/null
    # NO WINDOW. A -N bound here manufactures the exact alarm this function
    # exists to settle: on 2026-08-30 two lanes independently got a false
    # MISSING from a windowed subject grep on a healthy repo, because the fleet
    # pushed 864 commits in 12h and -400 covers barely four hours of that. The
    # failure direction is the expensive one -- the message below says "cherry-pick",
    # and a cherry-pick on a false reading manufactures a real duplicate.
    # Unbounded costs 0.65s over the full 17k-commit history. Measured, not assumed.
    landed=$(git log --format=%s "origin/$BRANCH" 2>/dev/null)
    missing=""
    while IFS= read -r subj; do
        [ -n "$subj" ] || continue
        printf '%s\n' "$landed" | grep -qxF "$subj" || missing="$missing
  $subj"
    done <<EOF
$manifest
EOF
    [ -n "$missing" ] || return 0

    echo "sync: *** $(printf '%s' "$missing" | grep -c .) OF $manifest_n COMMIT(S) DID NOT LAND ***" >&2
    echo "sync: expected on origin/$BRANCH but absent:$missing" >&2
    echo "sync:" >&2
    echo "sync: YOUR WORK IS NOT LOST -- it is in the reflog. Do NOT reset --hard." >&2
    echo "sync: find it and replay it onto current HEAD:" >&2
    echo "sync:     git reflog --date=iso | head -30      # look for 'commit:' lines" >&2
    echo "sync:     git cherry-pick <sha>                 # conflicts are normal here" >&2
    echo "sync: then re-run tools/sync.sh and check this line again." >&2
    exit 1
}

# A SECOND, DUMBER LOOK, sharing nothing with the first.
#
# bug-t-a-wrapped-resolve-citation-is-invisible-to-both-check-and-fill: frankC
# wrote an ordinary wrapped Log line --
#
#     - 2026-08-30 — reproduced at HEAD before claiming (all three cells), fixed,
#       resolved, commit PENDING-COMMIT.
#
# -- and it matched NEITHER progress.py's PENDING_RE nor this file's fill. So
# `check` reported no pending resolves, sync printed "pushed 1 commit(s), all
# verified on origin" with no `filled` line -- which is exactly what a ticket
# with nothing to fill looks like -- and the literal sat in the file forever.
# The placeholder was not unfilled. It was UNSEEN, in all three places anyone
# would look.
#
# That is the 2026-08-29 bug rotated. Back then the fill was a pair of sed
# literals covering fewer spellings than PENDING_RE, so check counted what fill
# could not fill and THE MISMATCHED NUMBERS WERE THE ALARM. Aligning them was
# right -- and it retired a differential test that had been running free on
# every input. Two divergent implementations of one predicate ARE an oracle;
# consolidating them deletes it, and nothing announces that.
#
# So the replacement oracle must share no assumption with the regex. Not a wider
# pattern -- a wider pattern only moves the boundary, and the next unanticipated
# spelling is silent again. A literal substring cannot be defeated by wrapping,
# indentation, or wording.
#
# SCOPE IS THE WHOLE DESIGN. Run over the tree, this fires on the seven files
# that merely DISCUSS the placeholder -- and a guard that cries wolf on prose is
# a guard that gets scrolled past. It looks only at ticket files THIS RUN'S
# COMMITS TOUCHED, so it fires once, on the sync that resolved the ticket, and
# never again.
#
# TWO CONDITIONS, and conflating them would hide the interesting one:
#   (a) `pending` NAMED the file and the literal survived -> the fill is broken.
#       Unambiguous, and the only one that earns a non-zero exit.
#   (b) `pending` never named it and the literal is there -> either the regex is
#       blind to this spelling, or the line is prose. WARN and PRINT THE LINE.
#       One glance settles which, which is a better answer than any pattern I
#       could write to guess it -- and it keeps a false positive from carrying
#       an exit code, which is what would teach people to ignore the real one.
#
# Never exit non-zero for (b): the push already SUCCEEDED. Reporting a healthy
# push as a failure is this file's own recorded failure mode wearing the other
# hat, and the defect here is silence -- a line that names the file ends it.
verify_citations_landed() {
    # BOTH inputs, because this function now answers two questions and they have
    # different sources. Keying the early-out on manifest_tickets alone made the
    # nudge unreachable whenever that list was empty -- harmless live, since
    # manifest_resolved is a subset of it, but the devtest passes the two
    # separately and caught it in the first run. Accidentally correct is not
    # correct.
    [ -n "$manifest_tickets" ] || [ -n "$manifest_resolved" ] || return 0
    # STILL OWED, not "was owed". Asking `pending` again AFTER the fill is the
    # only honest form of condition (a), and the first cut got it wrong in a way
    # its own devtest could not see: it asked whether `pending` had named the
    # file BEFORE, and whether the literal is present NOW. A ticket that carried
    # a real placeholder AND quotes the placeholder in its prose satisfies both
    # while being perfectly healthy -- the citation filled, the prose stayed.
    #
    # It fired on the very commit that introduced it, whose write-up quotes the
    # literal five times, and cried FILL FAILED at a successful fill. Caught by
    # running it, not by reading it: every fixture had one or the other, and the
    # bug lives only where a file has both.
    still_owed=$(python3 "$(dirname "$0")/progress.py" pending 2>/dev/null \
                 | cut -f1 || true)
    # TWO QUESTIONS, TWO CANDIDATE SETS. The first cut walked one list for both
    # and that was the calibration bug: `manifest_tickets` is every ticket the
    # push TOUCHED, and the family index is touched on most pushes while being a
    # document ABOUT citations, so it always contains strings shaped like one.
    # The coordinator got the unwrap-it advice on every push it made, about
    # narrative prose, and it was never actionable. Mention versus use, one level
    # down from the regression-/decide-/grant- exclusion in the nudge below.
    #
    #   (a) is the fill broken?     -> ask `pending`. Its answer is authoritative
    #                                  and cannot contain prose. Intersected with
    #                                  this push so we do not nag about another
    #                                  lane's backlog.
    #   (b) is a placeholder unseen? -> only tickets this push RESOLVED. A
    #                                  wrapped citation can only be written by
    #                                  the resolve that moved the ticket, so
    #                                  nothing else is a candidate, and a
    #                                  document that merely discusses the
    #                                  mechanism is never resolved by this push.
    broken="" ; unseen=""
    for f in $still_owed; do
        [ -n "$f" ] || continue
        printf '%s\n' "$manifest_tickets" | grep -qxF "$f" || continue
        broken="$broken
  $f"
    done
    for f in $manifest_resolved; do
        [ -f "$f" ] || continue          # renamed or removed since; nothing to read
        printf '%s\n' "$still_owed" | grep -qxF "$f" && continue   # (a) owns it
        # BARE occurrences only. A real citation is bare; a document quoting the
        # placeholder writes `PENDING-COMMIT` or **PENDING-COMMIT**, and a
        # resolved ticket whose SUBJECT is this machinery is otherwise the one
        # remaining false positive.
        hits=$(grep -nE "(^|[^\`*])$PLACEHOLDER([^\`*]|\$)" "$f" 2>/dev/null \
               | head -2 | cut -c1-120 | sed 's/^/      /')
        [ -n "$hits" ] || continue
        unseen="$unseen
  $f: $hits"
    done

    if [ -n "$unseen" ]; then
        echo "sync: NOTE — $PLACEHOLDER is still in a ticket this push RESOLVED," >&2
        echo "sync: and \`progress.py pending\` did not see it. Read the line: if it is" >&2
        echo "sync: prose about the placeholder, ignore this; if it is a real citation," >&2
        echo "sync: PENDING_RE is blind to its spelling and the sha will never be filled." >&2
        echo "sync: Unwrapping it onto one line is the fix, and re-running sync fills it.$unseen" >&2
    fi
    # THE SILENT SIBLING. A ticket resolved by a hand-typed Log line never gets
    # a placeholder, so the fill has nothing to fill and `check` nothing to
    # count: uncited, and nothing anywhere says so. Strictly worse than
    # PENDING-COMMIT, which at least greps, counts, and has a tool that repairs
    # it.
    #
    # This lives HERE, not in progress.py's `check`, and the scope is the whole
    # reason. As a standing report over the tree it is worthless: 31 uncited
    # tickets in the freshest six days, 456 before August, and no date floor
    # rescues it -- measured, and it is why
    # bug-t-a-resolve-that-never-wrote-a-placeholder-is-uncited-and-nothing-says-so
    # was closed `rejected/`. The SAME findings are worth having one at a time,
    # addressed to the person who just resolved the ticket, at the moment fixing
    # it costs one line. Scope changes the value, not the count.
    #
    # Bias is opposite to the placeholder search above, on purpose: that one is a
    # literal because a missed spelling hides a real defect, this one is loose
    # because it is a nudge and a false alarm on somebody's write-up is the only
    # way it can do harm.
    # Calibrated against the live board, not guessed: over the last 400 commits
    # touching a resolved bucket, 469 resolutions, 43 would nudge -- 9%. But 23
    # of those 43 are `regression-`, `decide-` and `grant-` slugs, whose
    # resolution IS a verdict rather than a commit: the watcher files and closes
    # regression tickets from tstate, a decision closes when the user rules, a
    # grant when it is returned. Nudging those teaches that uncited means
    # nothing, which is the third caution exactly. Excluded by prefix, and the
    # rate falls to 19 of 469 -- 4%, roughly one nudge per twenty-five
    # resolutions, every one of them a `bug-`/`feature-` ticket that changed code
    # and cited nothing.
    uncited=""
    for f in $manifest_resolved; do
        [ -f "$f" ] || continue
        case "${f##*/}" in
            regression-*|decide-*|grant-*|meta-*|tstate-*|README*) continue ;;
        esac
        grep -qF "$PLACEHOLDER" "$f" 2>/dev/null && continue     # the fill owns it
        grep -Eqi "commits?[: ]+.?[0-9a-f]{7,40}" "$f" && continue
        uncited="$uncited
  $f"
    done
    if [ -n "$uncited" ]; then
        echo "sync: NOTE — resolved this push, citing no commit:$uncited" >&2
        echo "sync: nothing will ever ask again — \`check\` counts placeholders, and a" >&2
        echo "sync: hand-typed Log line never wrote one. Add \`, commit <sha>.\` to the Log" >&2
        echo "sync: entry; cite the FIX, not the close, and name the close beside it." >&2
        echo "sync: If the resolution was not a commit — profiled, declined, filed" >&2
        echo "sync: elsewhere — then it is correctly uncited and this line is noise." >&2
    fi

    if [ -n "$broken" ]; then
        echo "sync: *** FILL FAILED — these were owed a citation and still are ***$broken" >&2
        echo "sync: progress.py named them, the substitution ran, and the literal survived." >&2
        echo "sync: That is a bug in the fill, not in the ticket. Do not hand-edit around it." >&2
        exit 1
    fi
}

rebase_onto_origin

if [ "$PUSH" = "1" ]; then
    push_or_die
    verify_manifest_landed
    # Report what WE landed, not whatever HEAD happens to be. HEAD after a
    # rebase is frequently another lane's commit, and printing it is how a
    # dropped commit read as a successful push.
    if [ "$manifest_n" -gt 0 ]; then
        echo "sync: pushed $manifest_n commit(s), all verified on origin:"
        printf '%s\n' "$manifest" | sed 's/^/  /'
    else
        echo "sync: nothing of ours to push — origin/$BRANCH at $(git log --oneline -1 "origin/$BRANCH")"
    fi
    fill_pending_commits
    verify_citations_landed
else
    echo "sync: up to date — $(git log --oneline -1)"
fi

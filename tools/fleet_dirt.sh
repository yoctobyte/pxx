#!/usr/bin/env bash
# fleet_dirt.sh -- who is holding which shared compiler file, right now.
#
# The coordinator must answer "is this file free?" before granting it. The
# answer is worthless if the survey misses a checkout, and on 2026-08-29 it
# did: the scan was a hardcoded list of nine clone names, a session worked in
# a tenth (a worktree, ~/pxx-songfmt), and the coordinator granted a file that
# was being edited. Four checkouts were invisible to that list.
#
# So this DISCOVERS checkouts instead of naming them. A hardcoded enumeration
# is precisely the defect the audit ticket
# `bug-a-target-enumerations-in-comments-are-stale-and-one-of-them-hid-a-live-bug`
# is about, and a survey that names its own scope is the shape that goes stale
# silently -- an absent checkout looks exactly like a clean one.
#
#   tools/fleet_dirt.sh                 # every checkout, only shared-file dirt
#   tools/fleet_dirt.sh -a              # every checkout, ALL dirt
#   tools/fleet_dirt.sh -r ~/trees      # look somewhere other than the default
#
# Default root is the PARENT of this checkout, which is where the fleet lives.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        -a|--all)  ALL=1; shift ;;
        -r|--root) ROOT="$2"; shift 2 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "fleet_dirt: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

# The shared files two agents must never edit at once. Kept deliberately broad:
# a false hit costs one question, a miss costs a collision.
SHARED='compiler/(ir|symtab|defs|lexer|emit)[a-z0-9_]*\.inc|compiler/compiler\.pas|compiler/pasparser_|compiler/py(lexer|parser)|compiler/c(lexer|parser|preproc)|compiler/builtin/'

# AGE = minutes since the last commit in that tree. It is here because a tree's
# NAME is not evidence of who works in it, and on 2026-08-30 that cost a
# verification: ~/frankwasm is on branch `wasm`, 442 behind master, while the
# session called frankwasm actually works in ~/pxx-songfmt on master. Had a
# file been granted on the strength of ~/frankwasm looking clean, the survey
# would have been 442 commits out of date and confidently wrong.
#
# The fix is deliberately NOT a name->tree mapping. A mapping is a second
# sentence that can drift from the thing it describes, which is the failure
# this whole script exists to avoid. Age is derived from the tree's own
# history, so a live tree identifies itself and a dormant one cannot pretend.
# Read it as: minutes, `-` for no commits, and anything over a few hours in a
# tree you were told is active means you are looking at the wrong tree.
# How far back a tree's own commits still count as "probably still there".
RECENT_MIN=${FLEET_RECENT_MIN:-90}

found=0
printf '%-24s %-10s %-7s %s\n' CHECKOUT BRANCH AGE 'HELD FILES'
printf '%-24s %-10s %-7s %s\n' ------------------------ ---------- ------- -----------

for d in "$ROOT"/*/; do
    [ -e "$d/.git" ] || continue
    [ -f "$d/compiler/compiler.pas" ] || continue
    found=$((found + 1))
    name=$(basename "$d")
    branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
    ct=$(git -C "$d" log -1 --format=%ct 2>/dev/null)
    if [ -n "$ct" ]; then
        age=$(( ( $(date +%s) - ct ) / 60 ))
        if [ "$age" -lt 1440 ]; then age="${age}m"; else age="$((age / 1440))d"; fi
    else
        age='-'
    fi
    if [ "$ALL" = 1 ]; then
        dirt=$(git -C "$d" status --short 2>/dev/null | awk '{print $NF}')
    else
        dirt=$(git -C "$d" status --short 2>/dev/null | awk '{print $NF}' \
               | grep -E "$SHARED")
    fi

    # RECENTLY COMMITTED shared files, marked with a trailing (*).
    #
    # Uncommitted dirt alone is a FALSE NEGATIVE and it produced a bad dispatch
    # on 2026-08-30: a lane that had held ir_codegen.inc all session, and had
    # said so twice, read as holding nothing because it happened to be between
    # edits when the scan ran. It had committed and pushed four minutes earlier.
    # "Idle" and "committed four minutes ago" are indistinguishable from
    # outside, and a working tree is clean for most of a lane's life.
    #
    # The reflog is what makes this per-TREE rather than per-BRANCH: every
    # checkout shares master, so `git log` shows everyone's commits everywhere,
    # but a tree's own reflog lists only the commits THAT TREE made, with unix
    # timestamps. So this is derived from the tree, like the age column, and
    # cannot drift from a mapping someone has to maintain.
    #
    # A window, not a lock: a lane that committed inside FLEET_RECENT_MIN
    # minutes is probably still working there. Ask before granting; do not read
    # (*) as either free or held.
    recent=$(git -C "$d" reflog show --date=unix HEAD 2>/dev/null \
             | sed -n 's/^\([0-9a-f]*\) HEAD@{\([0-9]*\)}: commit[:(].*/\1 \2/p' \
             | awk -v now="$(date +%s)" -v w="$RECENT_MIN" 'now - $2 < w * 60 {print $1}' \
             | head -40 \
             | while read -r sha; do
                   git -C "$d" show --name-only --format= "$sha" 2>/dev/null
               done \
             | grep -E "$SHARED" | sort -u)
    if [ -n "$recent" ]; then
        recent=$(printf '%s\n' "$recent" | sed 's/$/ (*)/')
        if [ -n "$dirt" ]; then dirt=$(printf '%s\n%s' "$dirt" "$recent"); else dirt="$recent"; fi
    fi
    if [ -n "$dirt" ]; then
        printf '%-24s %-10s %-7s %s\n' "$name" "$branch" "$age" "$(echo "$dirt" | head -1)"
        echo "$dirt" | tail -n +2 | while read -r f; do
            printf '%-24s %-10s %-7s %s\n' '' '' '' "$f"
        done
    else
        printf '%-24s %-10s %-7s %s\n' "$name" "$branch" "$age" '-'
    fi
done

if [ "$found" = 0 ]; then
    echo "fleet_dirt: no pxx checkouts under $ROOT -- wrong root?" >&2
    exit 1
fi
echo
echo "$found checkout(s) discovered under $ROOT. A (*) file was COMMITTED by that tree recently, not dirty now. A checkout absent from this"
echo "list is indistinguishable from a clean one -- if a session names a tree"
echo "that is not here, find out where it actually is before granting a file."

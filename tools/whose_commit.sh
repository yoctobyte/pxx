#!/bin/sh
# whose_commit.sh <sha>... -- name the checkout that CREATED each commit.
#
# A WRAPPER. The implementation is `tools/whoholds.py --sha`, which already held
# this logic before this file existed -- the reflog verb set, the exclusion of
# membership verbs, the ambiguity handling and the where-not-who caveat. Two
# copies of one verb set drift silently and had already diverged on their first
# day, so the verb set lives in exactly one place now and this is the front door.
#
# WHY A FRONT DOOR AT ALL: whoholds.py is named and documented for FILE HOTNESS,
# so nobody holding an attribution question ever found the answer inside it, and
# a second implementation got written by someone who had read the (then stale)
# method in CLAUDE.md instead. The name is the discoverability, and it is worth
# fifteen lines of shell.
#
# THE SCAN SET IS frankH'S AND IT MOVED INTO whoholds.py WITH THIS MERGE: not a
# `frank*` glob (`~/pxx` and `~/trackt-watch` are this repo too, and the watcher
# clone authors every auto-filed regression -- globbing seat names denied 4056
# origin/master shas), and not a bare `*/.git` walk either (`~/pxx-website` is a
# different repository). Enumerate, and keep the clones whose origin URL matches
# ours -- self-configuring, rather than a second list that goes stale the way the
# first one did.
#
# Exits 1 if ANY sha is unresolved -- both shapes, nobody claims it and two claim
# it -- because a tool that confidently names one seat when two trees claim the
# object is worse than one that refuses. A name gets believed.
#
# Caveat no reflog can lift, printed on every run: this says WHERE a commit was
# authored, never WHO authored it. The Claude-Session trailer fails differently
# and is printed beside the checkout for that reason, not as a fallback -- a
# sync.sh PENDING-COMMIT fill-in is authored in a real checkout and is
# trailerless, so the reflog sees it and the URL cannot.
set -u
[ $# -gt 0 ] || { echo "usage: $0 <sha>..." >&2; exit 2; }
exec "$(dirname "$0")/whoholds.py" --sha "$@"

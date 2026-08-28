#!/bin/sh
# Every ticket this branch has filed must also exist on origin/master.
#
# WHY THIS IS A CHECK AND NOT A NOTE. Two Track A tickets were filed from this
# branch and committed here — including a p70 for a heap that starts at address
# zero — and were therefore invisible to `tools/progress.sh ready|next`, to the
# ranker, and to whoever takes Track A next. I reported one of them to the
# coordinator as "filed on master". It was not.
#
#   Filing a ticket on a branch is filing it nowhere. A p70 you cannot rank is
#   worse than an unfiled one, because you believe it is handled.
#
# Ticket files are the fleet's shared index, not lane artifacts: the CODE may
# live on a branch, the TICKET may not. Writing that down is what failed the
# first time — this lane has now produced three defects of exactly that family
# (a rule written at the emitter and broken in the planner, a pipe hazard
# documented and then walked into, a null-guard hazard written down and not
# connected to the allocator). Writing it down moves nothing; making the wrong
# form unrepresentable does.
#
# Local ref only, no fetch: this runs in the ordinary test loop and must not
# need the network. A stale origin/master can only make this check LATE, never
# wrong — a ticket that reached master since the last fetch is reported as
# missing, and the fix for that is a fetch.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
cd "$root"

tmp=${TMPDIR:-/tmp}/pxx-wasm-tickets.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

if ! git rev-parse --verify -q origin/master >/dev/null; then
  echo "ok  no origin/master ref here — nothing to compare (not a pass)"
  echo "PASS check_tickets"
  exit 0
fi

# Compared by SLUG, not by path. A ticket's directory is its STATE — master
# moves tickets between backlog/working/done/rejected constantly — so a
# path-wise comparison reports every ticket master has resolved since the last
# merge as one this branch invented. Measured: the first version of this check
# named eleven such files and none of them were mine, which would have trained
# me to ignore it inside a day. A check that cries wolf is worse than no check,
# for the same reason a diagnostic that names a cause is: it does your
# reasoning for you, wrongly.
#
# BOARD.md and BOARD-brief.md are GENERATED and legitimately differ.
git ls-tree -r --name-only origin/master -- devdocs/progress \
  | sed 's|.*/||' | sort -u > "$tmp/master.txt"

missing=""
# The WORKING TREE, not HEAD: --cached lists tracked and staged-new files,
# --others the untracked ones. A ticket that exists as a file is a ticket
# somebody is about to believe in, and catching it before the commit is
# strictly better than catching it after — the real incident was a COMMITTED
# ticket, but only because nothing looked earlier.
for f in $(git ls-files --cached --others --exclude-standard -- devdocs/progress \
           | grep -v '^devdocs/progress/BOARD'); do
  grep -qxF "${f##*/}" "$tmp/master.txt" || missing="$missing $f"
done

if [ -n "$missing" ]; then
  echo "FAIL these exist on this branch and NOT on origin/master:"
  for f in $missing; do echo "       $f"; done
  echo "     A ticket that is not on master does not exist. Land them there:"
  echo "       git checkout master && git checkout <branch> -- <file>"
  echo "       tools/progress.sh board-md && git commit && git push"
  echo "     (If origin/master is stale, git fetch first.)"
  exit 1
fi
echo "ok  every ticket on this branch is also on origin/master"

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_tickets"

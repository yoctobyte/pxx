#!/bin/sh
# whose_commit.sh <sha>... -- name the checkout that CREATED each commit.
#
# Matches a CREATING verb in each checkout's reflog, not plain membership and
# not the bare word `commit`. tools/sync.sh rebases nearly every sync, so a
# commit that raced is replayed: the sha `git commit` minted is discarded and
# the sha on origin -- the only one anybody quotes -- is born under
# `rebase (pick)` or `rebase (continue)`. Matching `^<sha> commit` denied 46%
# of one session's arc on 2026-09-06, pin v405 included.
#
# Membership verbs (rebase (start), pull, reset, checkout, merge) MOVE a ref
# and never mint an object; they are excluded, which is the whole point.
#
# Caveat that no reflog can lift: this says WHERE a commit was authored, never
# WHO authored it. A cherry-pick or one session applying another's patch puts
# the wrong tree behind the sha. Corroborate with the Claude-Session trailer.
set -u
# `rebase` is not the only prefix a rebase step wears: run under `git pull
# --rebase`, git prefixes the step with the PULL's action, so the entry reads
# `pull --rebase -q (pick): <subject>` and a `^rebase \(` pattern denies it.
# Six spellings are live in these checkouts right now. Hence `pull\b[^:()]*`.
# A BARE `pull ...` with no step suffix stays excluded -- that is membership,
# and matching it names every checkout that ever pulled the sha.
STEP='\((pick|continue|fixup|squash|reword|edit|revert)\)'
CREATE="(commit|commit \(amend\)|commit \(initial\)|(rebase|pull\b[^:()]*) $STEP)"
root=${PXX_CHECKOUT_ROOT:-$HOME}

[ $# -gt 0 ] || { echo "usage: $0 <sha>..." >&2; exit 2; }

rc=0
for sha in "$@"; do
  short=$(git rev-parse --short=9 "$sha" 2>/dev/null) || { echo "$sha  UNKNOWN-SHA"; rc=1; continue; }
  claim=
  for d in "$root"/frank*/; do
    [ -d "$d.git" ] || continue
    if git -C "$d" reflog --format='%h %gs' 2>/dev/null \
         | grep -qE "^$short $CREATE"; then
      claim="$claim $(basename "$d")"
    fi
  done
  id=$(git log -1 --format=%B "$sha" 2>/dev/null | sed -n 's|.*/\(session_[A-Za-z0-9]*\).*|\1|p' | head -1)
  n=$(echo $claim | wc -w)
  case $n in
    0) echo "$short  NO CHECKOUT CLAIMS IT  ${id:-no-session-id}"
       echo "      -> not authored under $root, or its reflog has expired (90d default)." ; rc=1 ;;
    1) echo "$short $claim  ${id:-no-session-id}" ;;
    *) echo "$short  AMBIGUOUS:$claim  ${id:-no-session-id}"
       echo "      -> a patch applied in two trees. The session id is the tiebreak." ; rc=1 ;;
  esac
done
exit $rc

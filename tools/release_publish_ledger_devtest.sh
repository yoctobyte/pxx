#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Devtest for tools/release.sh publish(): the codename ledger is COMMITTED and
# PUSHED, and the tag is made on THAT commit, so a publish leaves a clean tree
# and a tag that carries its own CODENAMES line.
# Real git throughout, against a scratch bare repository standing in for
# origin. Nothing leaves this machine: gh is a shell function that only
# records, and git's global config is isolated.
#   1. success: origin's branch holds the ledger commit; the tag exists on
#      origin, points at that commit and its tree has the line; the local tree
#      is clean; the release workflow was dispatched (recorded, not run).
#   2. origin refuses the branch push (a pre-receive hook, standing in for
#      "origin moved"): nothing tagged locally or on origin, the ledger commit
#      dropped (HEAD back on origin's tip), the tree clean, the line gone.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REL="$PWD/tools/release.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
ok()  { echo "  PASS $1"; }
bad() { echo "  FAIL $1 -- $2"; fail=1; }

mkdir -p "$T/pin"
head -c 4096 /dev/urandom > "$T/pin/pinned"; echo 1 > "$T/pin/VERSION"
cp "$T/pin/pinned" "$T/compiler"

# fresh <name>: a bare origin and a clone of it with one commit on master.
fresh() {
  git init -q --bare -b master "$T/$1.git"
  git clone -q "$T/$1.git" "$T/$1" 2>/dev/null
  ( cd "$T/$1" && echo x > f && git add f && git commit -q -m init && git push -q origin master )
}
# publish_in <name>: publish v9.9.9 there, answering the seatbelt and the
# typed confirmation on stdin.
publish_in() {
  ( cd "$T/$1" || exit 1
    source <(sed '$d' "$REL")
    REPO_ROOT="$T/$1"; COMPILER="$T/compiler"; PIN_DIR="$T/pin"; LOCAL=0; SEATBELT=1
    gh() { echo "gh $*" >> "$T/gh.calls"; return 0; }
    publish v9.9.9 Testname
  ) < <(printf 'y\nn\nn\nv9.9.9\n') 2>&1
}

fresh ok
out=$(publish_in ok); rc=$?
L="$T/ok"; O="$T/ok.git"
line=$(git -C "$O" show v9.9.9:devdocs/release-notes/CODENAMES 2>/dev/null)
tagc=$(git -C "$O" rev-parse -q --verify 'v9.9.9^{commit}')
tip=$(git -C "$O" rev-parse master)
[ "$rc" = 0 ] && [ "$line" = "v9.9.9 Testname" ] && [ -n "$tagc" ] && [ "$tagc" = "$tip" ] \
  && [ -z "$(git -C "$L" status --porcelain)" ] \
  && [ "$(git -C "$O" log -1 --format=%s master)" = "release: v9.9.9, codename Testname" ] \
  && grep -q '^gh workflow run release.yml -f tag=v9.9.9$' "$T/gh.calls" \
  && ok "publish: ledger committed and pushed, tag on that commit carries the line, tree clean" \
  || bad "publish" "rc=$rc line=[$line] tag=$tagc tip=$tip status=[$(git -C "$L" status --porcelain)] $out"

fresh moved
printf '#!/bin/sh\nwhile read o n r; do case "$r" in refs/heads/*) echo "origin moved" >&2; exit 1;; esac; done\n' \
  > "$T/moved.git/hooks/pre-receive"
chmod +x "$T/moved.git/hooks/pre-receive"
before=$(git -C "$T/moved.git" rev-parse master)
out=$(publish_in moved); rc=$?
L="$T/moved"; O="$T/moved.git"
[ "$rc" != 0 ] && echo "$out" | grep -q 'nothing tagged, CODENAMES commit dropped' \
  && [ -z "$(git -C "$O" tag -l v9.9.9)" ] && [ -z "$(git -C "$L" tag -l v9.9.9)" ] \
  && [ "$(git -C "$L" rev-parse HEAD)" = "$before" ] && [ "$(git -C "$O" rev-parse master)" = "$before" ] \
  && [ -z "$(git -C "$L" status --porcelain)" ] && [ ! -e "$L/devdocs/release-notes/CODENAMES" ] \
  && ok "origin refuses the push: nothing tagged anywhere, commit dropped, tree clean" \
  || bad "origin moved" "rc=$rc head=$(git -C "$L" rev-parse HEAD) before=$before status=[$(git -C "$L" status --porcelain)] $out"

[ "$fail" = 0 ] && echo "release_publish_ledger_devtest: all green" || { echo "release_publish_ledger_devtest: RED"; exit 1; }

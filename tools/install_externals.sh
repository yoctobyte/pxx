#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Fetch third-party source trees into external/ (gitignored).
#
# Same policy as tools/install_lib_candidates.sh, which is the sibling tool for
# library_candidates/: third-party source NEVER lives in the repo — only the
# tool that installs it on demand — and each tree is PINNED to an upstream
# commit and gets a PROVENANCE.md recording it. Two roots rather than one
# because they mean different things: library_candidates/ holds corpora we
# compile to test the compiler, external/ holds libraries that test recipes
# link against (`make lib-test` builds test/lib_synapse.pas with
# -Fuexternal/synapse).
#
# Usage:
#   tools/install_externals.sh            # fetch anything missing
#   FORCE=1 tools/install_externals.sh    # re-fetch even if present
#
# Run this in a fresh clone before `make lib-test`, or answer yes to the
# Synapse question in ./install.sh, which calls this script.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
EXTERNAL_DIR="$ROOT/external"
FORCE="${FORCE:-0}"

# Pinned upstream version (bump here, re-run).
SYNAPSE_REPO="${SYNAPSE_REPO:-https://github.com/geby/synapse.git}"
SYNAPSE_COMMIT="b3224c3d133a39c3c22decc24a20a7e0fd62fddc"   # master, 2026-08 snapshot

SYNAPSE_DIR="$EXTERNAL_DIR/synapse"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git required"
mkdir -p "$EXTERNAL_DIR"

# Shallow-fetch exactly one commit, with no .git left behind: the tree is a
# pinned artifact, not a checkout to develop in. Bumping the pin above and
# re-running is the only supported way to move it — which is the whole point,
# since a tree that tracked origin/master left no two checkouts guaranteed to
# hold the same source.
fetch_commit() {  # $1=url $2=destdir $3=commit
  url="$1"; dest="$2"; commit="$3"
  say "fetching $(basename "$dest") @ $commit"
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" remote add origin "$url"
  git -C "$tmp" fetch -q --depth 1 origin "$commit"
  git -C "$tmp" checkout -q FETCH_HEAD
  rm -rf "$dest"; mkdir -p "$dest"
  ( cd "$tmp" && tar --exclude=.git -cf - . ) | ( cd "$dest" && tar -xf - )
  rm -rf "$tmp"
}

if [ -d "$SYNAPSE_DIR" ] && [ "$FORCE" != 1 ]; then
  say "synapse present at $SYNAPSE_DIR (FORCE=1 to re-fetch) — skip"
else
  fetch_commit "$SYNAPSE_REPO" "$SYNAPSE_DIR" "$SYNAPSE_COMMIT"
  cat > "$SYNAPSE_DIR/PROVENANCE.md" <<EOF
# Synapse
Upstream: ${SYNAPSE_REPO}
Commit: ${SYNAPSE_COMMIT}
Installed by tools/install_externals.sh. Vendor source — gitignored, never committed.
License: see synafpc.pas headers (BSD-style, Lukas Gebauer).
EOF
  say "synapse -> $SYNAPSE_DIR"
fi

say "external/ ready. Build synapse-using code with:  --mimic-fpc -Fuexternal/synapse"

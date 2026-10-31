#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# pxx_latest.sh -- print the path of the LATEST compiler, compiler/pascal26 of
# this checkout, after making sure it is built from the sources in the tree.
#
#   PXX="$("$PXX_HOME_DIR/tools/pxx_latest.sh")"
#
# Apps build with latest, never the pin: the pin is the self-host seed, and a
# program that breaks on latest is a pxx bug or regression to fix, not a
# reason to stay on an old compiler. The compiler and lib/ then come from the
# same tree by construction.
#
# compiler/pascal26 went stale whenever a tree was pulled and not rebuilt.
# The fixedpoint stamp records the source hash and the binary's sha256, so a
# fresh build is two hashes (~0.2s); only a mismatch runs make. A seed too old
# to compile the current sources is reseeded from the pin and built again.
# Build output goes to stderr; stdout is only the path. Exit 1 when the build
# fails.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPILER="$ROOT/compiler/pascal26"
STAMP="$ROOT/compiler/.pascal26.fixedpoint"

fresh() {
  [ -x "$COMPILER" ] && [ -f "$STAMP" ] || return 1
  src="$(cd "$ROOT" && tools/compiler_srchash.sh)"
  [ -n "$src" ] || return 1
  [ "$src" = "$(sed -n 's/^srchash //p' "$STAMP")" ] || return 1
  [ "$(sha256sum "$COMPILER" | cut -d' ' -f1)" = "$(sed -n 's/^sha256 //p' "$STAMP")" ]
}

if ! fresh; then
  # two app builds at once must not run two makes in one tree
  exec 9>"$ROOT/compiler/.pxx_latest.lock"
  flock 9
  if ! fresh; then
    echo "pxx_latest: compiler/pascal26 is stale, rebuilding" >&2
    if ! nice -n 15 make -s -C "$ROOT" "compiler/pascal26" >&2; then
      echo "pxx_latest: build failed; reseeding from the pin and retrying" >&2
      nice -n 15 make -s -C "$ROOT" seed-from-stable >&2
      nice -n 15 make -s -C "$ROOT" "compiler/pascal26" >&2 || {
        echo "pxx_latest: latest does not build from the pin either" >&2; exit 1; }
    fi
  fi
fi
echo "$COMPILER"

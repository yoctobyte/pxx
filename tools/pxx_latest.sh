#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# pxx_latest.sh -- print the compiler an app builds with.
#
#   PXX_HOME_DIR="$("$HOME/pxx/tools/pxx_latest.sh" --home)"
#   PXX="$PXX_HOME_DIR/compiler/pascal26"
#   RTL="$PXX_HOME_DIR/lib/rtl"             # same root as the compiler, always
#
# Channels (see tools/pxx_publish_latest.sh for the three compilers):
#   latest (default)  the newest gate-tested build, $PXX_FROZEN_DIR/latest
#   PXX_CHANNEL=dev   this checkout's live compiler, rebuilt here if stale;
#                     for a session fixing a bug together with pxx
#
# Without --home it prints the compiler's path. Either way stderr names the
# channel and the compiler's sha, so a result can be tied to a binary.
#
# dev: compiler/pascal26 went stale whenever a tree was pulled and not rebuilt.
# The fixedpoint stamp records the source hash and the binary's sha256, so a
# fresh build costs two hashes (~0.2s); only a mismatch runs make. A seed too
# old to compile the current sources is reseeded from the pin and rebuilt.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FROZEN="${PXX_FROZEN_DIR:-$HOME/pxx-frozen}"
CHANNEL="${PXX_CHANNEL:-latest}"
WANT=compiler
[ "${1:-}" = --home ] && WANT=home

fresh() {
  [ -x "$COMPILER" ] && [ -f "$STAMP" ] || return 1
  src="$(cd "$ROOT" && tools/compiler_srchash.sh)"
  [ -n "$src" ] || return 1
  [ "$src" = "$(sed -n 's/^srchash //p' "$STAMP")" ] || return 1
  [ "$(sha256sum "$COMPILER" | cut -d' ' -f1)" = "$(sed -n 's/^sha256 //p' "$STAMP")" ]
}

case "$CHANNEL" in
  latest)
    HOME_DIR="$(cd "$FROZEN/latest" 2>/dev/null && pwd -P)" || {
      echo "pxx_latest: no tested latest at $FROZEN/latest; a green tools/gate.sh publishes one" >&2
      echo "  (or PXX_CHANNEL=dev for the live tree)" >&2
      exit 1; }
    COMPILER="$HOME_DIR/compiler/pascal26"
    ;;
  dev)
    HOME_DIR="$ROOT"
    COMPILER="$ROOT/compiler/pascal26"
    STAMP="$ROOT/compiler/.pascal26.fixedpoint"
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
            echo "pxx_latest: the live tree does not build from the pin either" >&2; exit 1; }
        fi
      fi
    fi
    ;;
  *)
    echo "pxx_latest: PXX_CHANNEL must be latest or dev, not '$CHANNEL'" >&2
    exit 1
    ;;
esac

sha="$(sha256sum "$COMPILER" | cut -c1-12)"
echo "pxx: $CHANNEL $sha ($HOME_DIR)" >&2
if [ "$WANT" = home ]; then echo "$HOME_DIR"; else echo "$COMPILER"; fi

#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# pxx_publish_latest.sh -- publish this checkout's TESTED compiler as "latest".
#
# Three compilers, three jobs (owner, 2026-11-01):
#   dev     the live tree's compiler/pascal26. It moves under active work.
#           PXX_CHANNEL=dev tools/pxx_latest.sh
#   latest  the newest commit whose gate passed. This is what apps build with.
#           tools/pxx_latest.sh
#   pinned  stable_linux_amd64/default/pinned: the self-host seed. It is not
#           for apps; a stale pin cost a week of wrong measurements.
#
# gate.sh calls this after a GREEN verdict. It refuses unless the binary was
# built from the committed tree: no tracked change under compiler/ or lib/,
# and the fixedpoint stamp matches both the sources and the binary. It then
# copies the binary, compiler/builtin and lib/ (~17 MB) to
# $PXX_FROZEN_DIR/latest-<sha> and moves the `latest` link there. The copy is
# what apps run, so it is exactly what the gate tested. The newest 5 latest-*
# are kept.
#
#   tools/pxx_publish_latest.sh          publish, or say why not (exit 1)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FROZEN="${PXX_FROZEN_DIR:-$HOME/pxx-frozen}"
KEEP=5
COMPILER="$ROOT/compiler/pascal26"
STAMP="$ROOT/compiler/.pascal26.fixedpoint"

cd "$ROOT"
if [ -n "$(git status --porcelain --untracked-files=no -- compiler lib)" ]; then
  echo "pxx_publish_latest: tracked changes under compiler/ or lib/; not publishing an uncommitted build" >&2
  exit 1
fi
src="$(tools/compiler_srchash.sh)"
bin="$(sha256sum "$COMPILER" | cut -d' ' -f1)"
if [ -z "$src" ] || [ "$src" != "$(sed -n 's/^srchash //p' "$STAMP")" ] ||
   [ "$bin" != "$(sed -n 's/^sha256 //p' "$STAMP")" ]; then
  echo "pxx_publish_latest: compiler/pascal26 is not the fixedpoint of this tree; run make first" >&2
  exit 1
fi
sha="$(git rev-parse --short=10 HEAD)"
name="latest-$sha"
mkdir -p "$FROZEN"
if [ ! -d "$FROZEN/$name" ]; then
  tmp="$FROZEN/.$name.tmp"
  rm -rf "$tmp"
  mkdir -p "$tmp/compiler"
  cp -p "$COMPILER" "$tmp/compiler/pascal26"
  cp -Rp compiler/builtin "$tmp/compiler/builtin"
  cp -Rp lib "$tmp/lib"
  printf 'commit %s\nsha256 %s\npublished %s\n' "$(git rev-parse HEAD)" "$bin" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp/VERSION"
  mv "$tmp" "$FROZEN/$name"
fi
# swap the link atomically: a build starting mid-publish sees old or new, never neither
ln -sfn "$name" "$FROZEN/.latest.new"
mv -T "$FROZEN/.latest.new" "$FROZEN/latest"
echo "pxx_publish_latest: latest -> $name (compiler ${bin%"${bin#????????????}"})"

# keep the newest $KEEP; never the one just published
ls -1dt "$FROZEN"/latest-* 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  [ "$(basename "$old")" = "$name" ] || rm -rf "$old"
done

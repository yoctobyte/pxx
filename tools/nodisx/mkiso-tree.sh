#!/bin/sh
# mkiso-tree.sh OUT: assemble what the Nodisx ISO carries for the on-site
# build, from $NODISX_WORK: every recorded recipe (recipe/<tool>/), exactly
# the tarballs their sources.list files name (dl/, sha256 checked), the
# driver (onsite-all.sh), and pxx (pxx/: the compiler binary and the
# compiler/ and lib/ sources it reads at run time -- pxx finds its library
# relative to its own path). Files are hard-linked where the filesystem
# allows, else copied.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/mkiso-tree.sh /data/tmp/iso
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
OUT=${1:?usage: mkiso-tree.sh OUT}
ROOT=$(cd "$T/../.." && pwd)
PXXBIN=${PXX:-$ROOT/compiler/pascal26}
[ ! -e "$OUT" ] || { echo "mkiso-tree: $OUT exists" >&2; exit 1; }
mkdir -p "$OUT/recipe" "$OUT/dl" "$OUT/pxx/compiler"
put() { ln "$1" "$2" 2>/dev/null || cp -p "$1" "$2"; }
n=0
for r in "$W"/recipe/*/; do
  t=$(basename "$r")
  [ -f "$r/onsite.sh" ] && [ -f "$r/sources.list" ] || continue
  cp -pR "$r" "$OUT/recipe/$t"
  while read -r name sum; do
    [ -n "$name" ] || continue
    echo "$sum  $W/dl/$name" | sha256sum -c - > /dev/null || { echo "mkiso-tree: $t: $name: checksum mismatch" >&2; exit 1; }
    [ -e "$OUT/dl/$name" ] || put "$W/dl/$name" "$OUT/dl/$name"
  done < "$r/sources.list"
  n=$((n + 1))
done
cp "$T/onsite-all.sh" "$OUT/onsite-all.sh"
cp -p "$PXXBIN" "$OUT/pxx/compiler/pascal26"
( cd "$ROOT" && git ls-files compiler lib ) | while read -r f; do
  mkdir -p "$OUT/pxx/$(dirname "$f")"
  put "$ROOT/$f" "$OUT/pxx/$f"
done
git -C "$ROOT" rev-parse HEAD > "$OUT/pxx/COMMIT"
echo "mkiso-tree: $OUT ($n recipes, $(ls "$OUT/dl" | wc -l) tarballs, $(du -sh "$OUT" | cut -f1))"

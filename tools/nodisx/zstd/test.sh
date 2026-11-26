#!/bin/sh
# test.sh: PASS/FAIL for the zstd recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh as the target would, then:
#  1. runs zstd's own CLI suite (tests/playTests.sh, with datagen built by gcc)
#     on the pxx zstd and on the gcc zstd: PASS needs both to finish;
#  2. compresses a tarball, random data and datagen output with both builds
#     over a set of options (levels 1..19, --ultra -22, -T4, --long, a trained
#     dictionary) and compares the .zst files byte for byte, then decompresses
#     each with the other build;
#  3. decompresses every .tar.zst the downloads hold, if any.
# PASS is all three.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/zstd/test.sh
# Needs record.sh to have run, and make and bash (host only).
set -eu
export LC_ALL=C
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
R=$W/recipe/zstd
[ -f "$R/link" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/zstd-onsite
rm -rf "$O"
DL=$W/dl PXX=$PXX JOBS=${JOBS:-3} RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root"
REF=$W/zstd-ref
G=$REF/programs/zstd
Q=$O/work/zstd
fail=0

# 1. the suite, on both builds (playTests.sh stops at the first failure)
make -C "$REF/tests" datagen > "$O/datagen.log" 2>&1
DG=$REF/tests/datagen
for b in gcc pxx; do
  if [ $b = gcc ]; then z=$G; else z=$Q; fi
  # a whole tree: the suite reads ../tests/golden-* beside itself
  mkdir -p "$O/suite-$b"
  cp -a "$REF/." "$O/suite-$b/"
  if ( cd "$O/suite-$b/tests" && ZSTD_BIN=$z DATAGEN_BIN=$DG bash ./playTests.sh ) > "$O/suite-$b.log" 2>&1; then
    echo "zstd playTests.sh ($b): pass"
  else
    echo "zstd playTests.sh ($b): FAIL, last lines:"; tail -5 "$O/suite-$b.log"; fail=1
  fi
done

# 2. compression byte for byte, and each build reads the other's output
I=$O/in
mkdir -p "$I"
zcat "$W/dl/$(cut -d' ' -f1 "$R/sources.list")" > "$I/src.tar"
head -c 3000000 /dev/urandom > "$I/rand.bin"
"$DG" -g20000000 -P50 > "$I/gen.bin"
mkdir -p "$I/dict"
i=0
while [ $i -lt 200 ]; do printf '{"id": %d, "name": "item%d", "tags": ["a", "b%d"]}\n' $i $i $((i % 7)) > "$I/dict/s$i.json"; i=$((i + 1)); done
"$G" -q --train "$I"/dict/*.json -o "$I/dict.g"; "$Q" -q --train "$I"/dict/*.json -o "$I/dict.q"
cmp -s "$I/dict.g" "$I/dict.q" || { echo "--train: dictionaries DIFFER"; fail=1; }
n=0
for f in src.tar rand.bin gen.bin; do
  for o in "-1" "-3" "-9" "-19" "--ultra -22" "-3 -T4" "-19 -T4" "--long=27 -5" "-6 -D $I/dict.g"; do
    # shellcheck disable=SC2086
    "$G" -q -c $o "$I/$f" > "$I/out.g"; "$Q" -q -c $o "$I/$f" > "$I/out.q"
    cmp -s "$I/out.g" "$I/out.q" || { echo "compress $f [$o]: DIFFERS"; fail=1; }
    case $o in *-D*) d="-D $I/dict.g" ;; --long*) d="--long=27" ;; *) d= ;; esac
    # shellcheck disable=SC2086
    "$Q" -q -dc $d "$I/out.g" | cmp -s - "$I/$f" || { echo "pxx -d of gcc $f [$o]: DIFFERS"; fail=1; }
    # shellcheck disable=SC2086
    "$G" -q -dc $d "$I/out.q" | cmp -s - "$I/$f" || { echo "gcc -d of pxx $f [$o]: DIFFERS"; fail=1; }
    n=$((n + 1))
  done
done
[ "$fail" = 0 ] && echo "compress: $n cases and --train, all identical to gcc's and read back by both"

# 3. any .tar.zst at hand
for f in "$W"/dl/*.tar.zst; do
  [ -e "$f" ] || continue
  a=$("$G" -dc "$f" | sha256sum); b=$("$Q" -dc "$f" | sha256sum)
  if [ "$a" = "$b" ]; then echo "decompress $(basename "$f"): same"; else echo "decompress $(basename "$f"): DIFFERS"; fail=1; fi
done
size "$Q" | sed "s|$O/work/||"
if [ "$fail" = 0 ]; then echo "zstd recipe: PASS"; else echo "zstd recipe: FAIL"; exit 1; fi

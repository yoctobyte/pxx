#!/bin/sh
# test.sh: PASS/FAIL for the dosfstools recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh as the target would, then:
#  1. runs dosfstools' own suite (`make check`: reference images for FAT12/
#     16/32 and Atari, fsck repairs of broken images, label tests) with the
#     pxx binaries in place of the gcc ones, in a copy of the reference tree;
#  2. formats images with both builds over a set of options (--invariant, so
#     the output is deterministic) and compares them byte for byte, and the
#     programs' output.
# PASS is both: the suite reports no FAIL, and every image and output is
# identical to gcc's.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/dosfstools/test.sh
# Needs record.sh to have run, and make and xxd (host only).
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
R=$W/recipe/dosfstools
[ -f "$R/units" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/dosfstools-onsite
rm -rf "$O"
DL=$W/dl PXX=$PXX RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root"
REF=$W/dosfstools-ref
fail=0

# 1. the suite, on the pxx binaries
mkdir -p "$O/suite"
cp -a "$REF/." "$O/suite/"
for p in mkfs.fat fsck.fat fatlabel; do cp "$O/work/bin/$p" "$O/suite/src/$p"; touch "$O/suite/src/$p"; done
( cd "$O/suite" && make -k check ) > "$O/check.log" 2>&1 || true
s=$(grep -E '^# (TOTAL|PASS|FAIL|XFAIL|ERROR):' "$O/check.log" | tr '\n' ' ')
echo "dosfstools suite: $s"
grep -q '^# FAIL: *0$' "$O/check.log" && grep -q '^# ERROR: *0$' "$O/check.log" \
  && ! grep -q '^# PASS: *0$' "$O/check.log" || fail=1
# make must not have rebuilt them from source
for p in mkfs.fat fsck.fat fatlabel; do cmp -s "$O/work/bin/$p" "$O/suite/src/$p" || { echo "test: make rebuilt $p"; fail=1; }; done

# 2. images and output against gcc's
n=0; bad=0
I=$O/img
mkdir -p "$I"
while read -r kb args; do
  for b in gcc pxx; do
    bin=$REF/src/mkfs.fat; [ $b = pxx ] && bin=$O/work/bin/mkfs.fat
    : > "$I/$b.img"
    truncate -s "${kb}K" "$I/$b.img"
    # stdout and stderr compared apart: crtl's stdout is unbuffered, so the
    # two interleave differently from glibc's when they share a pipe
    # (feature-c-crtl-stdio-buffering-and-setvbuf)
    # shellcheck disable=SC2086
    "$bin" --invariant $args "$I/$b.img" > "$I/$b.out" 2> "$I/$b.err" && echo rc=0 >> "$I/$b.out" || echo "rc=$?" >> "$I/$b.out"
    fsck=$REF/src/fsck.fat; [ $b = pxx ] && fsck=$O/work/bin/fsck.fat
    "$fsck" -v -n "$I/$b.img" >> "$I/$b.out" 2>> "$I/$b.err" || true
    sed -i "s|$I/$b.img|IMG|" "$I/$b.out" "$I/$b.err"
  done
  n=$((n + 1))
  if cmp -s "$I/gcc.img" "$I/pxx.img" && cmp -s "$I/gcc.out" "$I/pxx.out" && cmp -s "$I/gcc.err" "$I/pxx.err"; then :; else
    bad=$((bad + 1)); echo "differs: $kb $args"; cmp "$I/gcc.img" "$I/pxx.img" | head -1
    diff "$I/gcc.out" "$I/pxx.out" | head -5; diff "$I/gcc.err" "$I/pxx.err" | head -5
  fi
done <<'EOF'
1440 -F 12
2880 -F 12 -n NODISX -i 0badcafe
32768 -F 16
65536 -F 16 -s 4 -S 1024
262144 -F 32
524288 -F 32 -n BOOT -R 64 -f 1
300000 -F 32 -a -h 63
40000 -A
EOF
echo "images: $n cases, $bad differ from gcc's"
[ "$bad" = 0 ] || fail=1
size "$O/work/bin/mkfs.fat" "$O/work/bin/fsck.fat" "$O/work/bin/fatlabel" | sed "s|$O/work/bin/||"
if [ "$fail" = 0 ]; then echo "dosfstools recipe: PASS"; else echo "dosfstools recipe: FAIL"; exit 1; fi

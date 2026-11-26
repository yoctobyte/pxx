#!/bin/sh
# test.sh: PASS/FAIL for the util-linux recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh as the target would, then:
#  1. runs util-linux's own test components for what the recipe builds
#     (tests/run.sh blkid fdisk sfdisk libfdisk libsmartcols lib md5 sha1
#     uuid partx: 50 tests, about 300 with their sub-tests) with the pxx
#     sfdisk, fdisk and blkid in place of gcc's, in a copy of the reference
#     tree, and once on gcc's own build; the helper programs (test_*,
#     sample-*) stay gcc's. `make check' itself refuses to start in this
#     configuration (it wants test_ttyutils, which --disable-all-programs
#     does not build), so run.sh is called with the components by name.
#  2. partitions images with both sfdisk builds from a set of scripts (GPT
#     and DOS, with the disk and partition ids fixed; one script mixes
#     positional and named fields, which sfdisk refuses, so its error path
#     is compared too), and compares the
#     images byte for byte, and sfdisk -d, fdisk -l and blkid -p on them,
#     stdout, stderr and the exit status apart.
# PASS is both: the same suite result as gcc's (no failure), every image and
# output identical to gcc's.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/util-linux/test.sh
# Needs record.sh to have run, and bash (tests/run.sh), host only.
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
R=$W/recipe/util-linux
[ -f "$R/link" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/util-linux-onsite
rm -rf "$O"
DL=$W/dl PXX=$PXX JOBS=${JOBS:-3} RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root"
REF=$W/util-linux-ref
B=$O/work/bin
fail=0
COMPONENTS="blkid fdisk sfdisk libfdisk libsmartcols lib md5 sha1 uuid partx"

# 1. the upstream tests, on gcc's build and on the pxx programs
for side in gcc pxx; do
  rm -rf "$O/suite-$side"
  mkdir -p "$O/suite-$side"
  cp -a "$REF/." "$O/suite-$side/"
  ( cd "$O/suite-$side" && make -j3 check-programs ) > "$O/check-programs-$side.log" 2>&1 \
    || { echo "test: make check-programs failed ($side)"; tail -5 "$O/check-programs-$side.log"; exit 1; }
  if [ $side = pxx ]; then
    for p in sfdisk fdisk blkid; do cp "$B/$p" "$O/suite-pxx/$p"; done
  fi
  # shellcheck disable=SC2086
  ( cd "$O/suite-$side" && tests/run.sh --srcdir="$PWD" --builddir="$PWD" --parallel=3 $COMPONENTS ) \
    > "$O/run-$side.log" 2>&1 || true
done
for side in gcc pxx; do
  s=$(grep -E 'tests PASSED|tests of .* FAILED' "$O/run-$side.log" | tail -1 | sed 's/^ *//')
  echo "util-linux tests ($side): $s, $(grep -cE '\.\.\. OK' "$O/run-$side.log") OK, $(grep -cE 'SKIPPED' "$O/run-$side.log") skipped"
done
grep -qE '^ *All [0-9]+ tests PASSED' "$O/run-pxx.log" || { grep -E 'FAILED' "$O/run-pxx.log" | head -20; fail=1; }
# the same tests ran and passed (a component that skips on one side only
# would hide a failure behind the count)
for side in gcc pxx; do
  grep -E '\.\.\. (OK|SKIPPED)' "$O/run-$side.log" | sed 's/  */ /g' | sort > "$O/results-$side.txt"
done
cmp -s "$O/results-gcc.txt" "$O/results-pxx.txt" || { echo "test: the per-test results differ from gcc's:"; diff "$O/results-gcc.txt" "$O/results-pxx.txt" | head -20; fail=1; }

# 2. partitioned images, byte for byte
I=$O/img
mkdir -p "$I"
n=0; same=0
while IFS='|' read -r size script; do
  n=$((n + 1))
  for b in gcc pxx; do
    if [ $b = gcc ]; then d=$REF; else d=$B; fi
    : > "$I/$b.img"; truncate -s "$size" "$I/$b.img"
    # (`&& echo rc 0 || echo rc $?': under set -e a failing command in a
    # { ...; echo; } list would end the script before the echo)
    { printf '%b' "$script" | "$d/sfdisk" --no-reread --no-tell-kernel "$I/$b.img" 2>&1 && echo "rc 0" || echo "rc $?"; } > "$I/$b.out"
    for c in "sfdisk -d" "sfdisk -l" "sfdisk -J" "sfdisk -V" "fdisk -l" "blkid -p -o export"; do
      # the image's path differs; the report must not
      # shellcheck disable=SC2086
      { "$d/${c%% *}" ${c#* } "$I/$b.img" 2>&1 && echo "rc 0" || echo "rc $?"; } >> "$I/$b.out"
    done
    sed -i "s|$I/$b.img|IMG|g" "$I/$b.out"
  done
  if cmp -s "$I/gcc.img" "$I/pxx.img" && cmp -s "$I/gcc.out" "$I/pxx.out"; then
    same=$((same + 1))
  else
    echo "sfdisk [$size $script]: DIFFERS"; diff "$I/gcc.out" "$I/pxx.out" | head -10; fail=1
  fi
done <<'EOF'
64M|label: gpt\nlabel-id: 11111111-2222-3333-4444-555555555555\nsize=16M, type=uefi, uuid=AAAAAAAA-0000-0000-0000-000000000001\ntype=linux, uuid=AAAAAAAA-0000-0000-0000-000000000002\n
64M|label: dos\nlabel-id: 0x12345678\n,8M,c,*\n,16M,83\n,,5\n,4M,83\n,,82\n
256M|label: gpt\nlabel-id: 0B0B0B0B-1111-2222-3333-444444444444\nfirst-lba: 2048\n1: size=32M, type=uefi, name="EFI system", uuid=CCCCCCCC-0000-0000-0000-000000000001\n2: size=64M, type=swap, uuid=CCCCCCCC-0000-0000-0000-000000000002\n3: type=linux, name="root", attrs="LegacyBIOSBootable", uuid=CCCCCCCC-0000-0000-0000-000000000003\n
128M|label: dos\nlabel-id: 0xdeadbeef\nunit: sectors\n2048,65536,L\n67584,,L\n
32M|label: gpt\nlabel-id: 99999999-8888-7777-6666-555555555555\nsector-size: 512\n,1M,21686148-6449-6E6F-744E-656564454649, uuid=DDDDDDDD-0000-0000-0000-000000000001\n,4M,L, uuid=DDDDDDDD-0000-0000-0000-000000000002\n,4M,L, uuid=DDDDDDDD-0000-0000-0000-000000000003\n,,L, uuid=DDDDDDDD-0000-0000-0000-000000000004\n
32M|label: gpt\nlabel-id: 99999999-8888-7777-6666-555555555556\nsize=1M, type=21686148-6449-6E6F-744E-656564454649, uuid=EEEEEEEE-0000-0000-0000-000000000001\nsize=4M, type=L, uuid=EEEEEEEE-0000-0000-0000-000000000002\nsize=4M, type=L, uuid=EEEEEEEE-0000-0000-0000-000000000003\ntype=L, uuid=EEEEEEEE-0000-0000-0000-000000000004\n
EOF
echo "sfdisk: $same of $n images, and their sfdisk/fdisk/blkid reports, identical to gcc's"
size "$B/sfdisk" "$B/fdisk" "$B/blkid" | sed "s|$B/||"
if [ "$fail" = 0 ]; then echo "util-linux recipe: PASS"; else echo "util-linux recipe: FAIL"; exit 1; fi

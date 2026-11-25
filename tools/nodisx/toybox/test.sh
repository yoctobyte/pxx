#!/bin/sh
# test.sh: PASS/FAIL for the toybox recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh exactly as the target would (a
# fresh work dir, the tarball from dl/, this tree's pxx), then runs toybox's
# own suite (scripts/test.sh, every applet) on that binary. PASS means the
# suite reports no FAIL -- the gcc build of the same configuration passes all
# of it (1604 tests on 0.8.15 + CONFIG_GZIP). Also extracts a tarball with
# --strip-components and compares the tree with GNU tar's, the on-site use.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/toybox/test.sh
# Needs record.sh to have run. The suite itself needs bash (host only).
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
R=$W/recipe/toybox
[ -f "$R/compile.list" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/toybox-onsite
rm -rf "$O"
DL=$W/dl PXX=$PXX RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root"
TB=$O/work/toybox

# toybox's suite runs from a source tree, against ./toybox
S=$O/suite
mkdir -p "$S"
read -r name sum < "$R/sources.list"
tar -xzf "$W/dl/$name" -C "$S" --strip-components=1
tar -xf "$R/gen.tar" -C "$S"
mkdir -p "$S/generated/unstripped"   # the suite builds scripts/install.c with host cc here
cp "$TB" "$S/toybox"
( cd "$S" && VERBOSE=all timeout 3000 bash scripts/test.sh ) > "$O/suite.log" 2>&1 < /dev/null || true
pass=$(grep -ac '^PASS:' "$O/suite.log" || true)
fail=$(grep -ac '^FAIL:' "$O/suite.log" || true)
echo "toybox suite: PASS $pass FAIL $fail"

# --strip-components extraction against GNU tar, on toybox's own tarball
mkdir -p "$O/x1" "$O/x2"
zcat "$W/dl/$name" | ( cd "$O/x1" && "$TB" tar -xf - --strip-components=1 )
tar -xzf "$W/dl/$name" -C "$O/x2" --strip-components=1
a=$(cd "$O/x1" && find . -type f -exec sha256sum {} + | sort -k2 | sha256sum)
b=$(cd "$O/x2" && find . -type f -exec sha256sum {} + | sort -k2 | sha256sum)
tarok=0; [ "$a" = "$b" ] && tarok=1
echo "toybox tar --strip-components matches GNU tar: $tarok"

if [ "$fail" = 0 ] && [ "$pass" -gt 1000 ] && [ "$tarok" = 1 ]; then
  echo "toybox recipe: PASS"
else
  grep -a '^FAIL:' "$O/suite.log" | head -20
  echo "toybox recipe: FAIL"
  exit 1
fi

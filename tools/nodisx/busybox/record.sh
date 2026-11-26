#!/bin/sh
# record.sh: write the busybox recipe that onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. busybox is Kbuild: kconfig and a
# handful of host-compiled generators (applet tables, usage text, config
# options) run here ONCE with gcc, on pixix's own configuration
# (pixix.config: the .config embedded in Rainyday's busybox-pxx2829, 394
# applets, FANCY_PING on). What they wrote travels in the recipe:
#   gen.tar  every header the build generated (include/autoconf.h,
#            applets.h, applet_tables.h, usage_compressed.h, bbconfigopts.h,
#            common_bufsiz.h, ...) and .config
#   units    one line per object: obj, directory (.), source, its -D/-I/
#            -include flags, from the `make V=1` log
#   link     busybox and its objects: applets/applets.o plus exactly the
#            archive members gcc's link pulled (busybox_unstripped.map), so
#            pxx links what upstream's link links, with no archives
# The gcc build stays in $W/busybox-ref for test.sh.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/busybox/record.sh
set -eu
LC_ALL=C; export LC_ALL   # sort and comm must agree (C order, not the locale's)
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=busybox-1.36.1.tar.bz2
"$T/../fetch.sh" "$TARBALL"
REF=$W/busybox-ref
R=$W/recipe/busybox
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
tar -xjf "$W/dl/$TARBALL" -C "$REF" --strip-components=1
cd "$REF"
cp "$T/pixix.config" .config
yes "" | make oldconfig > "$W/busybox-oldconfig.log" 2>&1
# the configuration must be pixix's exactly: oldconfig may not add or drop one
grep '^CONFIG' .config | sort > "$W/busybox-cfg.now"
grep '^CONFIG' "$T/pixix.config" | sort > "$W/busybox-cfg.want"
cmp -s "$W/busybox-cfg.now" "$W/busybox-cfg.want" || { echo "record: oldconfig changed pixix.config" >&2; diff "$W/busybox-cfg.want" "$W/busybox-cfg.now" >&2; exit 1; }
make -j"${JOBS:-3}" V=1 busybox > "$W/busybox-build.log" 2>&1
[ -x busybox ] || { echo "record: gcc build made no busybox" >&2; exit 1; }

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
# units: every `gcc -Wp,-MD,... -c -o OBJ SRC` (Kbuild compiles from the top)
awk '$1 == "gcc" && $2 ~ /^-Wp,-MD,/ && / -c -o / {
  obj = ""; src = $NF; fl = ""
  for (i = 2; i < NF; i++) {
    w = $i
    if (w == "-o") { obj = $(i + 1); i++; continue }
    if (w == "-include") { fl = fl " -include " $(i + 1); i++; continue }
    if (w ~ /^-[DUI]/) fl = fl " " w
  }
  print obj, ".", src fl
}' "$W/busybox-build.log" > "$R/units"
# link: applets.o (the only object in a built-in.o) and the members pulled
{ printf 'busybox applets/applets.o'
  sed -n 's|^\([a-z0-9_/-]*\)/lib\.a(\([^)]*\.o\)).*|\1/\2|p' busybox_unstripped.map | sort -u | tr '\n' ' ' | sed 's/^/ /; s/ $//'
  echo; } > "$R/link"
for o in $(cut -d' ' -f2- "$R/link"); do
  grep -q "^$o " "$R/units" || { echo "record: $o is linked but no unit compiles it" >&2; exit 1; }
done
# every header the build generated (not in the tarball), and .config
tar -tjf "$W/dl/$TARBALL" | sed 's|^[^/]*/||' | sort > "$W/busybox-tarball.list"
find . -name '*.h' ! -path './include/config/*' | sed 's|^\./||' | sort > "$W/busybox-h.list"
gen=$(comm -23 "$W/busybox-h.list" "$W/busybox-tarball.list" | tr '\n' ' ')
# shellcheck disable=SC2086
tar -cf "$R/gen.tar" .config $gen
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units; busybox links $(($(wc -w < "$R/link") - 1)) objects; generated: $gen)"

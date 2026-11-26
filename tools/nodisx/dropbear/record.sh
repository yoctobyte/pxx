#!/bin/sh
# record.sh: write the dropbear recipe (SSH server, client, key tool and scp)
# that onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. dropbear's autoconf configure and
# make run here ONCE, with the configuration tools/dropbear_pxx.py has proven
# under pxx (no zlib; no utmp/wtmp/lastlog login records; CFLAGS -Os, which
# keeps libtommath's 64-bit digits and its mode(TI) 128-bit word). What they
# decided travels in the recipe, PRE-GENERATED:
#   gen.tar   config.h, default_options_guard.h (made by make from
#             default_options.h)
#   units     one line per object (../lib/units-from-make.sh, from the make
#             log), -D_FORTIFY_SOURCE dropped (crtl has no _chk functions)
#   link      one line per program: its own objects, then the libtomcrypt and
#             libtommath members gcc's linker actually pulled, read from a
#             link map (-Wl,-Map), because pxx --link takes objects, not
#             archives, and the archives hold ~560 members
# The gcc build stays in $W/dropbear-ref.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/dropbear/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=dropbear-2026.94.tar.bz2
PROGS="dropbear dbclient dropbearkey scp"
"$T/../fetch.sh" "$TARBALL" > /dev/null
REF=$W/dropbear-ref
R=$W/recipe/dropbear
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
bzcat "$W/dl/$TARBALL" | tar -xf - -C "$REF" --strip-components=1
cd "$REF"
CFLAGS='-Os -W -Wall' ./configure --disable-zlib --disable-utmp --disable-utmpx \
  --disable-wtmp --disable-wtmpx --disable-lastlog --disable-pututline \
  --disable-pututxline --disable-loginfunc > "$W/dropbear-configure.log" 2>&1
# -j1: units-from-make follows make's directory lines, which -j interleaves
make -j1 PROGRAMS="$PROGS" $PROGS > "$W/dropbear-build.log" 2>&1
for p in $PROGS; do [ -x "$p" ] || { echo "record: gcc build made no $p" >&2; exit 1; }; done

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
# shellcheck disable=SC2086
sh "$T/../lib/units-from-make.sh" "$REF" "$W/dropbear-build.log" $PROGS > "$W/dropbear-units.txt"
awk '/^%%$/ { exit } { print }' "$W/dropbear-units.txt" | sed 's/ -D_FORTIFY_SOURCE=[0-9]*//' > "$R/units"
: > "$R/link"
for p in $PROGS; do
  # the program's own objects (everything but the archive members), and
  # gcc's link of exactly those plus the archives, with a map
  own=$(awk -v p="$p" '/^%%$/ { s = 1; next } s && $1 == p { for (i = 2; i <= NF; i++) if ($i !~ /^libtom(crypt|math)\//) printf " %s", $i }' "$W/dropbear-units.txt")
  # shellcheck disable=SC2086
  gcc -Wl,-Map="$W/dropbear-$p.map" -o "$W/dropbear-$p.gcc" $own \
    libtomcrypt/libtomcrypt.a libtommath/libtommath.a -lcrypt
  # each pulled member, by its name, to the one unit that wrote it
  members=$(grep -oE '(libtomcrypt|libtommath)\.a\([^)]*\.o\)' "$W/dropbear-$p.map" | sort -u |
    awk -v units="$R/units" '
      BEGIN { while ((getline l < units) > 0) { split(l, f, " "); o = f[1]; n = o; sub(/.*\//, "", n); lib = o; sub(/\/.*/, "", lib); key[lib "/" n] = key[lib "/" n] " " o; cnt[lib "/" n]++ } }
      { lib = $0; sub(/\.a\(.*/, "", lib); m = $0; sub(/.*\(/, "", m); sub(/\)$/, "", m)
        k = lib "/" m
        if (cnt[k] != 1) { print "record: archive member " $0 " matches " cnt[k] + 0 " units" > "/dev/stderr"; exit 1 }
        printf "%s", key[k] }')
  echo "$p$own$members" >> "$R/link"
done
grep -q "$REF" "$R/units" "$R/link" && { echo "record: a host path is left in the recipe" >&2; exit 1; }
tar -cf "$R/gen.tar" config.h default_options_guard.h
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units recorded)"
while read -r p objs; do
  # shellcheck disable=SC2086
  set -- $objs
  echo "  $p links $# objects"
done < "$R/link"

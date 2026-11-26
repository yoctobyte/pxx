#!/bin/sh
# record.sh: write the GNU make recipe that onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. GNU make is autoconf + automake;
# configure and one verbose `make` run here ONCE, and what they decided
# travels in the recipe, PRE-GENERATED:
#   config.h, lib/*.h (gen.tar)  what configure wrote (config.h, and the
#                                gnulib headers it generates: alloca.h, ...)
#   units               one line per object: obj, directory, source, its -D/-I
#                       flags (../lib/units-from-make.sh, from the make log)
#   link                the make program's objects, libgnu.a expanded
# Four of configure's answers are given as pxx's own, the ones configure
# would reach with pxx as CC:
#   --disable-posix-spawn  crtl has no posix_spawn; make then forks and
#                          execs, its long-standing path
#   --disable-load         no `load` directive (dlopen of make plugins): the
#                          bootstrap builds static programs
#   gl_cv_c_bool=no        gcc 15 is C23, where bool is a keyword; pxx is
#                          C11 and gets bool from <stdbool.h>
#   make_cv_sys_gnu_glob=no  crtl's glob() is POSIX's, without GNU's
#                          GLOB_ALTDIRFUNC and gl_opendir: make builds the
#                          glob and fnmatch it ships
# and --without-guile, --disable-nls. Everything else configure finds pxx
# provides; a crtl change that removes one shows up as a compile error on
# site. The gcc build stays in $W/make-ref for test.sh.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/make/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=make-4.4.1.tar.gz
"$T/../fetch.sh" "$TARBALL"
REF=$W/make-ref
R=$W/recipe/make
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
tar -xzf "$W/dl/$TARBALL" -C "$REF" --strip-components=1
cd "$REF"
gl_cv_c_bool=no make_cv_sys_gnu_glob=no \
  ./configure --disable-nls --without-guile --disable-posix-spawn --disable-load \
  > "$W/make-configure.log" 2>&1
make -j3 V=1 > "$W/make-build.log" 2>&1
[ -x make ] || { echo "record: gcc build made no make" >&2; exit 1; }

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
sh "$T/../lib/units-from-make.sh" "$REF" "$W/make-build.log" make \
  | awk -v u="$R/units" -v l="$R/link" '/^%%$/ { s = 1; next } { print > (s ? l : u) }'
grep -q 'MISSING-ARCHIVE' "$R/link" && { echo "record: an archive on the link line was not built in the log" >&2; exit 1; }
# every header configure generated (not in the tarball): config.h and the
# gnulib replacements under lib/
gen=src/config.h
for h in lib/*.h; do
  tar -tzf "$W/dl/$TARBALL" "make-4.4.1/$h" > /dev/null 2>&1 || gen="$gen $h"
done
# shellcheck disable=SC2086
tar -cf "$R/gen.tar" $gen
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units; make links $(($(wc -w < "$R/link") - 1)) objects; generated: $gen)"

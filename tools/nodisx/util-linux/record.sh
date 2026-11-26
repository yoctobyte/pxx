#!/bin/sh
# record.sh: write the util-linux recipe (sfdisk, fdisk, blkid) that
# onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. util-linux is automake + libtool;
# configure and one `make V=1` run here ONCE, and what they decided travels
# in the recipe, PRE-GENERATED:
#   gen.tar   every .c/.h the build GENERATED (config.h, blkid.h,
#             libfdisk.h, libsmartcols.h, ...): the built tree's sources that
#             are not in the upstream tarball
#   units     one line per object: obj, directory, source, its -D/-I flags
#             (../lib/units-from-make.sh, from the make log)
#   link      each program's objects, the archives expanded (libtool's
#             convenience copies of libcommon mapped back to its objects)
# configure: every program off but blkid and the fdisks, the libraries they
# need (libblkid, libfdisk, libsmartcols, libuuid) static and private, and
# none of the optional outside libraries (ncurses, readline, systemd, udev,
# libmagic, ...): no cfdisk, which needs a curses. configure's answers are
# glibc's, and pxx's crtl gives the same ones for every HAVE_<function>
# these programs use. The gcc build stays in $W/util-linux-ref for test.sh.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/util-linux/record.sh
set -eu
export LC_ALL=C   # sort and comm must agree on the order
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=util-linux-2.40.2.tar.xz
PROGS="sfdisk fdisk blkid"
"$T/../fetch.sh" "$TARBALL"
REF=$W/util-linux-ref
R=$W/recipe/util-linux
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
xz -dc "$W/dl/$TARBALL" | tar -xf - -C "$REF" --strip-components=1
cd "$REF"
./configure CFLAGS="-g -O2" --disable-all-programs \
    --enable-libblkid --enable-libfdisk --enable-libsmartcols --enable-libuuid \
    --enable-blkid --enable-fdisks=check --disable-shared --disable-nls \
    --without-ncursesw --without-ncurses --without-tinfo --without-readline \
    --without-systemd --without-udev --without-python --without-cap-ng \
    --without-libz --without-btrfs --without-selinux --without-econf \
    --without-libmagic --without-user --without-audit --without-smack \
    --disable-asciidoc --disable-poman \
    > "$W/util-linux-configure.log" 2>&1
make -j3 V=1 > "$W/util-linux-build.log" 2>&1
for p in $PROGS; do
  [ -x "$p" ] || { echo "record: gcc build made no $p" >&2; exit 1; }
done

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
# Which archive members ld LOADED for each program: its link command again,
# with -t -t, into a scratch output. libcommon and libuuid both carry
# lib/sha1.c and lib/md5.c, and pxx links objects, not archives, so the
# recipe must name the copy ld took (units-from-make.sh, TRACE).
TR=$W/util-linux-trace.txt
: > "$TR"
for p in $PROGS; do
  l=$(grep -E "^libtool: link: gcc .* -o $p " "$W/util-linux-build.log" | tail -1 | sed 's/^libtool: link: //')
  [ -n "$l" ] || { echo "record: no link command for $p in the log" >&2; exit 1; }
  l=$(echo "$l" | sed "s| -o $p | -o $W/util-linux-trace-$p.bin |")
  sh -c "$l -Wl,-t,-t" 2>&1 | grep '^(' | sed "s|^|$p |" >> "$TR"
done
# shellcheck disable=SC2086
TRACE=$TR sh "$T/../lib/units-from-make.sh" "$REF" "$W/util-linux-build.log" $PROGS \
  | awk -v u="$R/units" -v l="$R/link" '/^%%$/ { s = 1; next } { print > (s ? l : u) }'
grep -q 'MISSING-' "$R/link" && { echo "record: an archive or member on a link line was not built in the log" >&2; exit 1; }

# the generated sources: .c/.h in the built tree that the tarball lacks
xz -dc "$W/dl/$TARBALL" | tar -tf - | sed 's|^[^/]*/||' | sort > "$R/upstream.list"
find . -type f \( -name '*.c' -o -name '*.h' \) | sed 's|^\./||' | sort \
  | comm -23 - "$R/upstream.list" > "$R/generated.list"
tar -cf "$R/gen.tar" -T "$R/generated.list"
rm -f "$R/upstream.list"
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units, $(wc -l < "$R/generated.list") generated files)"
awk '{ printf "  %s links %d objects\n", $1, NF - 1 }' "$R/link"

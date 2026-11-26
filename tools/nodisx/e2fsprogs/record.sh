#!/bin/sh
# record.sh: write the e2fsprogs recipe (mke2fs, e2fsck, tune2fs) that
# onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. e2fsprogs is autoconf with its own
# Makefiles; configure and one `make V=1` run here ONCE, and what they
# decided travels in the recipe, PRE-GENERATED:
#   gen.tar   every .c/.h the build GENERATED (config.h, ext2fs.h,
#             ext2_err.c/.h from compile_et, crc32c_table.h,
#             default_profile.c, ...): the built tree's sources that are not
#             in the upstream tarball
#   units     one line per object: obj, directory, source, its -D/-I flags
#             (../lib/units-from-make.sh, from the make log)
#   link      each program's objects, the libraries' archives expanded
# configure: the private libuuid and libblkid (no host library), no NLS,
# fuse2fs, uuidd, libarchive, backtrace or TLS. debugfs and the other tools
# stay ON although the recipe takes only three programs: test.sh runs the
# upstream suite, which drives debugfs, and they change nothing in config.h.
# -std=gnu17: the host gcc defaults to C23, where e2fsprogs 1.47.1's
# `typedef int bool` (lib/ext2fs/tdb.c) is an error; pxx compiles it as is.
# configure's answers are glibc's, and pxx's crtl gives the same ones for
# every HAVE_<function> these programs use. The gcc build stays in
# $W/e2fsprogs-ref for test.sh.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/e2fsprogs/record.sh
set -eu
export LC_ALL=C   # sort and comm must agree on the order
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=e2fsprogs-1.47.1.tar.xz
PROGS="mke2fs e2fsck tune2fs"
"$T/../fetch.sh" "$TARBALL"
REF=$W/e2fsprogs-ref
R=$W/recipe/e2fsprogs
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
xz -dc "$W/dl/$TARBALL" | tar -xf - -C "$REF" --strip-components=1
cd "$REF"
./configure CFLAGS="-g -O2 -std=gnu17" --enable-libuuid --enable-libblkid \
    --disable-fuse2fs --disable-nls --disable-uuidd --without-libarchive \
    --disable-backtrace --disable-tls \
    > "$W/e2fsprogs-configure.log" 2>&1
make -j3 V=1 > "$W/e2fsprogs-build.log" 2>&1
for p in misc/mke2fs e2fsck/e2fsck misc/tune2fs; do
  [ -x "$p" ] || { echo "record: gcc build made no $p" >&2; exit 1; }
done

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
# shellcheck disable=SC2086
sh "$T/../lib/units-from-make.sh" "$REF" "$W/e2fsprogs-build.log" $PROGS \
  | awk -v u="$R/units" -v l="$R/link" '/^%%$/ { s = 1; next } { print > (s ? l : u) }'
grep -q 'MISSING-ARCHIVE' "$R/link" && { echo "record: an archive on a link line was not built in the log" >&2; exit 1; }

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

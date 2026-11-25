#!/bin/sh
# record.sh: write the mksh recipe that onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. mksh's Build.sh decides its
# configuration by compiling and running test programs, and needs `cc -E`,
# which pxx does not have. So Build.sh runs ONCE HERE, with gcc on the build
# host, and what it decided travels in the recipe, PRE-GENERATED:
#   flags          the -D list Build.sh settled on (one line)
#   gen.tar        rlimits.gen, sh_flags.gen, ulimits.gen, signames.inc
# The flags describe the build host's glibc. pxx's crtl provides everything
# they say is there (every unit compiles and mksh's own check.t gives the same
# result as the gcc build, see test.sh); a crtl change that removes something
# shows up as a compile error on site, not as a silent difference.
#
# Writes $NODISX_WORK/recipe/mksh/: sources.list, flags, units (the .c files,
# in Build.sh's link order), gen.tar, onsite.sh, RECIPE.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/mksh/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=mksh-R59c.tgz
"$T/../fetch.sh" "$TARBALL"
REF=$W/mksh-ref
R=$W/recipe/mksh
rm -rf "$REF" "$R"
mkdir -p "$REF/build" "$R"
tar -xzf "$W/dl/$TARBALL" -C "$REF"          # unpacks as mksh/
cd "$REF/build"
CC=gcc CFLAGS=-O2 sh ../mksh/Build.sh -r > "$W/mksh-build.log" 2>&1
[ -x mksh ] || { echo "record: Build.sh made no mksh" >&2; exit 1; }

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
line=$(grep -m1 -- ' -c \.\./mksh/lalloc\.c' Rebuild.sh)
flags=
for w in $line; do
  case $w in
    -I*) ;;                       # onsite.sh sets -I. and the source dir itself
    -D*) flags="$flags $w" ;;
  esac
done
echo "$flags" > "$R/flags"
grep -oE -- '-c \.\./mksh/[a-z0-9_]+\.c' Rebuild.sh | sed 's|.*/||' > "$R/units"
tar -cf "$R/gen.tar" rlimits.gen sh_flags.gen ulimits.gen signames.inc
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units)"

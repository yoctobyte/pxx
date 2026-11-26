#!/bin/sh
# record.sh: write the sqlite recipe that onsite.sh replays on the target.
#
# sqlite 3.46.0 (public domain): the sqlite3 command-line shell over the
# amalgamation, two units (sqlite3.c, shell.c). The version and the flags are
# pixix's (lib/stage-userland.sh in the pixx repo; the version is the one
# tools/install_lib_candidates.sh pins): -DSQLITE_THREADSAFE=0
# -DSQLITE_OMIT_LOAD_EXTENSION -DHAVE_READLINE=0. pixix fetches the
# amalgamation .zip, which toybox cannot unpack; the recipe takes the same
# release's autoconf .tar.gz, whose sqlite3.c, shell.c, sqlite3.h and
# sqlite3ext.h are byte-identical to that zip's (checked when this recipe was
# written; test.sh checks it again against the zip's pinned sha256 when the
# zip is in the download directory). Nothing is configured or generated.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/sqlite/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=sqlite-autoconf-3460000.tar.gz
"$T/../fetch.sh" "$TARBALL" > /dev/null
R=$W/recipe/sqlite
rm -rf "$R"
mkdir -p "$R"
echo "$TARBALL $(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)" > "$R/sources.list"
echo "-DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -DHAVE_READLINE=0" > "$R/flags"
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R (sqlite3.c + shell.c, pixix's flags: $(cat "$R/flags"))"

#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build the sqlite3 shell with only pxx, a POSIX
# shell and toybox-level tools (zcat, tar, sha256sum). Two units, the
# amalgamation and shell.c, compiled from inside the source directory with
# relative names, so __FILE__ in assert messages is "sqlite3.c", not a path.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/sqlite/onsite.sh /tmp/sqlite [/mnt/target]
#
# DL: the directory holding the tarball in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2; there are
# two). RECIPE: the recipe directory (default: this script's). With DESTDIR,
# installs bin/sqlite3. Exit status 0 only if both units compiled, sqlite3
# linked, and it reports the pinned version and answers a query.
set -eu
R=${RECIPE:-$(cd "$(dirname "$0")" && pwd)}
DL=${DL:?set DL to the directory with the source tarball}
PXX=${PXX:-pxx}
JOBS=${JOBS:-2}
WORK=${1:?usage: onsite.sh WORKDIR [DESTDIR]}
DEST=${2:-}

read -r name sum < "$R/sources.list"
echo "$sum  $DL/$name" | sha256sum -c - > /dev/null || { echo "onsite: $name: checksum mismatch" >&2; exit 1; }
mkdir -p "$WORK/src" "$WORK/obj"
zcat "$DL/$name" | tar -xf - -C "$WORK/src" --strip-components=1
read -r flags < "$R/flags"
cd "$WORK/src"
i=0
for u in sqlite3 shell; do
  # shellcheck disable=SC2086 -- the flags are words
  ( "$PXX" --emit-obj --function-sections --shared-runtime $flags -I. "$u.c" "$WORK/obj/$u.o" \
      > "$WORK/obj/$u.log" 2>&1 || : > "$WORK/obj/$u.fail" ) &
  i=$((i + 1))
  if [ "$i" -ge "$JOBS" ]; then wait; i=0; fi
done
wait
for u in sqlite3 shell; do
  [ ! -e "$WORK/obj/$u.fail" ] || { echo "onsite: FAILED $u.c: $(grep -m1 error "$WORK/obj/$u.log")" >&2; exit 1; }
done
"$PXX" --link -o "$WORK/sqlite3" "$WORK/obj/sqlite3.o" "$WORK/obj/shell.o" > "$WORK/link.log" 2>&1 \
  || { tail -5 "$WORK/link.log" >&2; exit 1; }

# smoke: the version in the tarball's name, and a query
want=$(echo "$name" | sed 's/^sqlite-autoconf-\([0-9]\)\([0-9][0-9]\)\([0-9][0-9]\).*/\1.\2.\3/; s/\.0\([0-9]\)/.\1/g')
got=$(echo 'select sqlite_version();' | "$WORK/sqlite3")
[ "$got" = "$want" ] || { echo "onsite: sqlite_version() is '$got', expected '$want'" >&2; exit 1; }
ans=$(echo 'create table t(x); insert into t values (20),(22); select sum(x) from t;' | "$WORK/sqlite3")
[ "$ans" = 42 ] || { echo "onsite: a query gave '$ans'" >&2; exit 1; }
echo "onsite: $WORK/sqlite3 ($got)"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin"
  cp "$WORK/sqlite3" "$DEST/bin/sqlite3"; chmod 755 "$DEST/bin/sqlite3"
  echo "onsite: installed into $DEST"
fi

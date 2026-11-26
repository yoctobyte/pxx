#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build dropbear, dbclient, dropbearkey and scp
# from the recipe with only pxx, a POSIX shell and toybox-level tools (bzcat,
# tar, sha256sum, sort). No gcc, make or configure: what configure decided was
# recorded on the build host (record.sh) and comes in gen.tar, `units` and
# `link`. The tarball is .tar.bz2: toybox's bzcat, or the bzip2 recipe's.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/dropbear/onsite.sh /tmp/dropbear [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# sbin/dropbear and bin/{dbclient,dropbearkey,scp}, and makes etc/dropbear/
# (host keys are generated on first start with -R, or by dropbearkey).
# Exit status 0 only if every unit compiled, every program linked and
# dropbearkey makes an ed25519 key.
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
bzcat "$DL/$name" | tar -xf - -C "$WORK/src" --strip-components=1
tar -xf "$R/gen.tar" -C "$WORK/src"

# every object some program links, once, JOBS at a time. A failed unit
# leaves OBJ.fail beside its log.
objs=$(cut -d' ' -f2- "$R/link" | tr ' ' '\n' | sort -u)
i=0
for obj in $objs; do
  line=$(grep -m1 "^$obj " "$R/units") || { echo "onsite: no unit for $obj" >&2; exit 1; }
  o=$WORK/obj/$(echo "$obj" | tr / _)
  (
    # shellcheck disable=SC2086 -- the flags are words, with configure's quoting
    set -- $line
    dir=$2; src=$3; shift 3
    cd "$WORK/src/$dir"
    eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime -ffile-prefix-map=\"\$WORK/src=/usr/src/dropbear\" $* \"\$src\" \"\$o\"" \
      > "$o.log" 2>&1 || : > "$o.fail"
  ) &
  i=$((i + 1))
  if [ "$i" -ge "$JOBS" ]; then wait; i=0; fi
done
wait
for f in "$WORK"/obj/*.fail; do
  [ -e "$f" ] || continue
  echo "onsite: FAILED $(basename "$f" .fail): $(grep -m1 error "${f%.fail}.log")" >&2
  exit 1
done
while read -r prog pobjs; do
  list=
  for obj in $pobjs; do list="$list $WORK/obj/$(echo "$obj" | tr / _)"; done
  # shellcheck disable=SC2086
  "$PXX" --link -o "$WORK/$prog" $list > "$WORK/link-$prog.log" 2>&1 \
    || { tail -5 "$WORK/link-$prog.log" >&2; echo "onsite: $prog did not link" >&2; exit 1; }
done < "$R/link"

# smoke: a key, generated and its public half printed back
rm -f "$WORK/smoke_ed25519"
"$WORK/dropbearkey" -t ed25519 -f "$WORK/smoke_ed25519" > /dev/null 2>&1 \
  && "$WORK/dropbearkey" -y -f "$WORK/smoke_ed25519" | grep -q '^ssh-ed25519 ' \
  || { echo "onsite: dropbearkey cannot make an ed25519 key" >&2; exit 1; }
echo "onsite: $WORK/dropbear $WORK/dbclient $WORK/dropbearkey $WORK/scp"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/sbin" "$DEST/bin" "$DEST/etc/dropbear"
  cp "$WORK/dropbear" "$DEST/sbin/dropbear"; chmod 755 "$DEST/sbin/dropbear"
  for p in dbclient dropbearkey scp; do cp "$WORK/$p" "$DEST/bin/$p"; chmod 755 "$DEST/bin/$p"; done
  chmod 700 "$DEST/etc/dropbear"
  echo "onsite: installed into $DEST"
fi

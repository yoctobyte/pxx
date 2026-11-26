#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build curl with mbedTLS from the recipe with
# only pxx, a POSIX shell and toybox-level tools (bzcat, xzcat, tar,
# sha256sum, sort). No gcc, make, libtool or configure: what configure
# decided was recorded on the build host (record.sh) and comes in gen.tar,
# `units` and `link`. mbedTLS is .tar.bz2 and curl .tar.xz, so the xz recipe
# (xzcat) comes first.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/curl/onsite.sh /tmp/curl [/mnt/target]
#
# DL: the directory holding the files named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs bin/curl
# and the CA bundle as etc/ssl/certs/ca-certificates.crt, the path curl was
# configured with. Exit status 0 only if every unit compiled, curl linked,
# reports mbedTLS and reads a file:// URL.
set -eu
R=${RECIPE:-$(cd "$(dirname "$0")" && pwd)}
DL=${DL:?set DL to the directory with the source tarballs}
PXX=${PXX:-pxx}
JOBS=${JOBS:-2}
WORK=${1:?usage: onsite.sh WORKDIR [DESTDIR]}
DEST=${2:-}

while read -r name sum; do
  echo "$sum  $DL/$name" | sha256sum -c - > /dev/null || { echo "onsite: $name: checksum mismatch" >&2; exit 1; }
done < "$R/sources.list"
mkdir -p "$WORK/src/mbedtls" "$WORK/src/curl" "$WORK/obj"
bzcat "$DL/$(grep -o '^mbedtls-[^ ]*' "$R/sources.list")" | tar -xf - -C "$WORK/src/mbedtls" --strip-components=1
xzcat "$DL/$(grep -o '^curl-[^ ]*' "$R/sources.list")" | tar -xf - -C "$WORK/src/curl" --strip-components=1
tar -xf "$R/gen.tar" -C "$WORK/src"

# compile the objects curl links, JOBS at a time. The threaded resolver is
# pthreads, hence --threadsafe. A failed unit leaves OBJ.fail beside its log.
read -r prog objs < "$R/link"
i=0
for obj in $objs; do
  line=$(grep -m1 "^$obj " "$R/units") || { echo "onsite: no unit for $obj" >&2; exit 1; }
  o=$WORK/obj/$(echo "$obj" | tr / _)
  (
    # shellcheck disable=SC2086 -- the flags are words, with configure's quoting
    set -- $line
    dir=$2; src=$3; shift 3
    cd "$WORK/src/$dir"
    eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime --threadsafe -ffile-prefix-map=\"\$WORK/src=/usr/src\" $* \"\$src\" \"\$o\"" \
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
list=
for obj in $objs; do list="$list $WORK/obj/$(echo "$obj" | tr / _)"; done
# shellcheck disable=SC2086
"$PXX" --link --threadsafe -o "$WORK/curl" $list > "$WORK/link.log" 2>&1 || { tail -5 "$WORK/link.log" >&2; exit 1; }

# smoke: it is built on mbedTLS and fetches a file:// URL
"$WORK/curl" -V | grep -q 'mbedTLS/' || { echo "onsite: curl -V does not report mbedTLS" >&2; exit 1; }
printf 'nodisx curl smoke\n' > "$WORK/smoke.txt"
"$WORK/curl" -sS "file://$WORK/smoke.txt" | cmp -s - "$WORK/smoke.txt" \
  || { echo "onsite: curl cannot read a file:// URL" >&2; exit 1; }
echo "onsite: $WORK/curl"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin" "$DEST/etc/ssl/certs"
  cp "$WORK/curl" "$DEST/bin/curl"; chmod 755 "$DEST/bin/curl"
  cp "$R/cacert.pem" "$DEST/etc/ssl/certs/ca-certificates.crt"
  chmod 644 "$DEST/etc/ssl/certs/ca-certificates.crt"
  echo "onsite: installed into $DEST"
fi

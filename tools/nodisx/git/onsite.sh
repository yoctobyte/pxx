#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build git, and git-remote-http on libcurl and
# mbedTLS, from the recipe with only pxx, a POSIX shell and toybox-level
# tools (xzcat, bzcat, tar, sha256sum). No gcc, make or configure: the
# choices were made on the build host (record.sh) and come in gen.tar,
# `units` and `link`. The tarballs are .tar.xz and .tar.bz2, so the xz and
# bzip2 recipes come first.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/git/onsite.sh /tmp/git [/mnt/target]
#
# DL: the directory holding the files named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs bin/git,
# libexec/git-core/ (git, git-remote-http and its https/ftp/ftps names) and
# share/git-core/templates, the paths record.sh gave git. https:// uses the
# CA bundle at etc/ssl/certs/ca-certificates.crt, which the curl recipe
# installs. Exit status 0 only if every unit compiled, both programs linked
# and git makes a repository with a commit in it.
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
mkdir -p "$WORK/src/zlib" "$WORK/src/mbedtls" "$WORK/src/curl" "$WORK/src/git" "$WORK/obj"
xzcat "$DL/$(grep -o '^zlib-[^ ]*' "$R/sources.list")" | tar -xf - -C "$WORK/src/zlib" --strip-components=1
bzcat "$DL/$(grep -o '^mbedtls-[^ ]*' "$R/sources.list")" | tar -xf - -C "$WORK/src/mbedtls" --strip-components=1
xzcat "$DL/$(grep -o '^curl-[^ ]*' "$R/sources.list")" | tar -xf - -C "$WORK/src/curl" --strip-components=1
xzcat "$DL/$(grep -o '^git-[^ ]*' "$R/sources.list")" | tar -xf - -C "$WORK/src/git" --strip-components=1
tar -xf "$R/gen.tar" -C "$WORK/src"

# every object either program links, once, JOBS at a time. libcurl's
# threaded resolver and git's preloaded index are pthreads: --threadsafe.
# A failed unit leaves OBJ.fail beside its log.
all=$(cut -d' ' -f2- "$R/link" | tr ' ' '\n' | sort -u)
i=0
for obj in $all; do
  line=$(grep -m1 "^$obj " "$R/units") || { echo "onsite: no unit for $obj" >&2; exit 1; }
  o=$WORK/obj/$(echo "$obj" | tr / _)
  (
    # shellcheck disable=SC2086 -- the flags are words, with the Makefiles' quoting
    set -- $line
    dir=$2; src=$3; shift 3
    cd "$WORK/src/$dir"
    ( eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime --threadsafe -ffile-prefix-map=\"\$WORK/src=/usr/src\" $* \"\$src\" \"\$o\"" \
      ) > "$o.log" 2>&1 || : > "$o.fail"
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
while read -r prog objs; do
  list=
  for obj in $objs; do list="$list $WORK/obj/$(echo "$obj" | tr / _)"; done
  # shellcheck disable=SC2086
  "$PXX" --link --threadsafe -o "$WORK/$prog" $list > "$WORK/link-$prog.log" 2>&1 \
    || { tail -5 "$WORK/link-$prog.log" >&2; exit 1; }
done < "$R/link"

# smoke: a repository with one commit, read back
"$WORK/git" --version | grep -q '^git version 2\.' || { echo "onsite: git --version failed" >&2; exit 1; }
s=$WORK/smoke
rm -rf "$s"; mkdir -p "$s"
( cd "$s" && HOME=$s GIT_CONFIG_NOSYSTEM=1 "$WORK/git" init -q . \
    && echo nodisx > f && "$WORK/git" add f \
    && HOME=$s GIT_CONFIG_NOSYSTEM=1 "$WORK/git" -c user.name=n -c user.email=n@n commit -qm smoke \
    && [ "$("$WORK/git" cat-file -p HEAD:f)" = nodisx ] ) \
  || { echo "onsite: git cannot make a commit" >&2; exit 1; }
"$WORK/git-remote-http" 2>&1 | grep -q 'remote-curl: usage' || { echo "onsite: git-remote-http does not start" >&2; exit 1; }
echo "onsite: $WORK/git"

if [ -n "$DEST" ]; then
  x=$DEST/libexec/git-core
  mkdir -p "$DEST/bin" "$x" "$DEST/share/git-core"
  cp "$WORK/git" "$DEST/bin/git"; chmod 755 "$DEST/bin/git"
  cp "$WORK/git" "$x/git"; chmod 755 "$x/git"
  for n in git-remote-http git-remote-https git-remote-ftp git-remote-ftps; do
    cp "$WORK/git-remote-http" "$x/$n"; chmod 755 "$x/$n"
  done
  rm -rf "$DEST/share/git-core/templates"
  cp -R "$WORK/src/git/templates/blt" "$DEST/share/git-core/templates"
  echo "onsite: installed into $DEST"
fi

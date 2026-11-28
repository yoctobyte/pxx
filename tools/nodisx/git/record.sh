#!/bin/sh
# record.sh: write the git recipe (git, and git-remote-http for http:// and
# https:// remotes) that onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. git has no configure: its Makefile
# takes the choices as make variables, given here rather than probed from
# this host. git-remote-http links libcurl, built on mbedTLS exactly as the
# curl recipe builds it (../curl/configure.args), and git links zlib. All four
# are built here once, and their logs are joined into one, so that
# lib/units-from-make.sh sees every archive being made and, with TRACE, the
# members ld loaded for each program (pxx --link takes objects, never an
# archive). The recipe:
#   units     one line per object: zlib's, mbedTLS's, libcurl's and git's
#   link      `git` and `git-remote-http` and their objects
#   gen.tar   what the builds generated that the tarballs lack: zlib's
#             zconf.h, mbedTLS's config as shipped (AES-NI on), curl's
#             curl_config.h, git's command-list.h, config-list.h,
#             hook-list.h and GIT-VERSION-FILE's version
# The choices:
#   prefix /, bindir /bin, gitexecdir /libexec/git-core, sysconfdir /etc,
#   template_dir /share/git-core/templates: the Nodisx layout (DESTDIR/bin)
#   NO_RUST    optional in git 2.x (Git 3.0 makes it required, and neither
#              pxx nor gcc compiles Rust: a recipe for 3.x needs rustc)
#   NO_PERL NO_PYTHON NO_TCLTK NO_GETTEXT NO_EXPAT
#              no interpreters on Nodisx's base, untranslated, no http-push
#   NO_OPENSSL git's own SHA-1 (sha1dc, collision detecting) and SHA-256
#   NO_ICONV   no re-encoding of commit messages in other charsets
#   NO_REGEX   git's bundled regex (compat/regex), which has REG_STARTEND
#   CURL_CONFIG=/bin/false, CURL_CFLAGS/CURL_LDFLAGS given: git would ask
#              THIS host's curl-config for its version (curl_check)
# The gcc builds stay in $W/git-ref for test.sh.
#
# JOBS: parallel gcc jobs (default 2).
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/git/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
ZLIB=zlib-1.4.tar.xz
MBED=mbedtls-3.6.8.tar.bz2
CURL=curl-8.23.0.tar.xz
GIT=git-2.56.1.tar.xz
"$T/../fetch.sh" zlib- mbedtls- curl- git- > /dev/null
REF=$W/git-ref
R=$W/recipe/git
rm -rf "$REF" "$R"
mkdir -p "$REF/zlib" "$REF/mbedtls" "$REF/curl" "$REF/git" "$REF/stage" "$R"
xzcat "$W/dl/$ZLIB" | tar -xf - -C "$REF/zlib" --strip-components=1
bzcat "$W/dl/$MBED" | tar -xf - -C "$REF/mbedtls" --strip-components=1
xzcat "$W/dl/$CURL" | tar -xf - -C "$REF/curl" --strip-components=1
xzcat "$W/dl/$GIT" | tar -xf - -C "$REF/git" --strip-components=1
S=$REF/stage
LOG=$W/git-build.log
: > "$LOG"
# one log for all four, each in its own `Entering directory` block
logdir() { echo "make: Entering directory '$1'" >> "$LOG"; }
logend() { echo "make: Leaving directory '$1'" >> "$LOG"; }

# zlib: its own configure (static only), installed into the stage
( cd "$REF/zlib" && CC=gcc ./configure --static --prefix="$S" ) > "$W/git-zlib-configure.log" 2>&1
logdir "$REF/zlib"
make -C "$REF/zlib" -j1 libz.a >> "$LOG" 2>&1
logend "$REF/zlib"
make -C "$REF/zlib" install > /dev/null 2>&1

# mbedTLS as the curl recipe builds it: the commands from a dry run (its
# own make echoes only "CC aes.c"), then the real build and the stage
logdir "$REF/mbedtls/library"
make -C "$REF/mbedtls/library" -n -B CC=gcc static 2>&1 | grep -v '^make' >> "$LOG"
logend "$REF/mbedtls/library"
make -C "$REF/mbedtls/library" -j"${JOBS:-2}" CC=gcc static > "$W/git-mbedtls-build.log" 2>&1
make -C "$REF/mbedtls" install DESTDIR="$S" > /dev/null 2>&1

# libcurl with the curl recipe's choices
# shellcheck disable=SC2046
( cd "$REF/curl" && CC=gcc ./configure --with-mbedtls="$S" $(cat "$T/../curl/configure.args") ) \
  > "$W/git-curl-configure.log" 2>&1
make -C "$REF/curl/lib" -j1 V=1 libcurl.la >> "$LOG" 2>&1
[ -f "$REF/curl/lib/.libs/libcurl.a" ] || { echo "record: gcc build made no libcurl.a" >&2; exit 1; }

GITVARS="prefix=/ bindir=/bin gitexecdir=/libexec/git-core sysconfdir=/etc
  template_dir=/share/git-core/templates
  NO_RUST=1 NO_PERL=1 NO_PYTHON=1 NO_TCLTK=1 NO_GETTEXT=1 NO_EXPAT=1
  NO_OPENSSL=1 NO_ICONV=1 NO_REGEX=1 SKIP_DASHED_BUILT_INS=1
  ZLIB_PATH=$S CURL_CONFIG=/bin/false CURL_CFLAGS=-I$REF/curl/include
  CC=gcc V=1"
# the archives as their builds made them (the log's `ar` lines), not the
# stage's copies, so units-from-make.sh knows their members
M=$REF/mbedtls/library
CURLLIBS="$REF/curl/lib/.libs/libcurl.a $M/libmbedtls.a $M/libmbedx509.a $M/libmbedcrypto.a -lpthread"
logdir "$REF/git"
# shellcheck disable=SC2086
make -C "$REF/git" -j"${JOBS:-2}" $GITVARS CURL_LDFLAGS="$CURLLIBS" git git-remote-http >> "$LOG" 2>&1
logend "$REF/git"
for p in git git-remote-http; do
  [ -x "$REF/git/$p" ] || { echo "record: gcc build made no $p" >&2; exit 1; }
done
# the templates `git init` copies (hooks samples, info/exclude, description):
# files with the shell path written in, no compiling
make -C "$REF/git/templates" SHELL_PATH=/bin/sh > /dev/null 2>&1
[ -f "$REF/git/templates/blt/description" ] || { echo "record: git made no templates" >&2; exit 1; }

for f in "$ZLIB" "$MBED" "$CURL" "$GIT"; do
  echo "$f $(sha256sum "$W/dl/$f" | cut -d' ' -f1)"
done > "$R/sources.list"

# which archive members ld loaded for each program: its link command again,
# with -t -t, into a scratch output (see units-from-make.sh, TRACE)
TR=$W/git-trace.txt
: > "$TR"
for p in git git-remote-http; do
  # make echoes it over several lines (`\` at each end): joined first
  l=$(awk '{ while (/\\$/ && (getline m) > 0) { sub(/\\$/, " "); $0 = $0 m } print }' "$LOG" \
    | grep -E "^gcc .* -o $p " | tail -1)
  [ -n "$l" ] || { echo "record: no link command for $p in the log" >&2; exit 1; }
  l=$(echo "$l" | sed "s| -o $p | -o $W/git-trace-$p.bin |")
  ( cd "$REF/git" && sh -c "$l -Wl,-t,-t" ) > "$W/git-trace-$p.log" 2>&1 \
    || { tail -3 "$W/git-trace-$p.log" >&2; echo "record: relinking $p failed" >&2; exit 1; }
  grep '^(' "$W/git-trace-$p.log" | sed "s|^|$p |" >> "$TR"
done
TRACE=$TR sh "$T/../lib/units-from-make.sh" "$REF" "$LOG" git git-remote-http \
  | awk -v u="$R/units" -v l="$R/link" '/^%%$/ { s = 1; next } { print > (s ? l : u) }'
grep -q 'MISSING-' "$R/link" && { grep -o 'MISSING-[^ ]*' "$R/link" | sort -u | head >&2; echo "record: an archive or member on a link line was not built in the log" >&2; exit 1; }
# zlib comes in as `-L... -lz` (git's Makefile adds -lz itself), which
# units-from-make.sh does not expand: its members, as the trace names them
awk -v tr="$TR" -v units="$R/units" '
  BEGIN { while ((getline l < units) > 0) { split(l, f, " "); if (f[1] ~ /^zlib\//) have[f[1]] = 1 }
          while ((getline l < tr) > 0) if (l ~ /libz\.a\)/) {
            p = l; sub(/ .*/, "", p); m = l; sub(/.*\)/, "", m)
            if (!(("zlib/" m) in have)) { print "record: zlib member " m " has no unit" > "/dev/stderr"; exit 1 }
            z[p] = z[p] " zlib/" m } }
  { print $0 z[$1] }' "$R/link" > "$R/link.new"
mv "$R/link.new" "$R/link"
for p in git git-remote-http; do
  grep "^$p " "$R/link" | grep -q ' zlib/inflate\.o' || { echo "record: $p links no zlib" >&2; exit 1; }
done
# glibc's fallbacks: a libgit.a member that gcc built with NO symbols because
# its source saw glibc (`#if ... __GNU_LIBRARY__`: compat/obstack.c elides
# itself when libc has obstack) was never loaded, so the trace leaves it out.
# Built by pxx against crtl it is the code, and git needs it
# (_obstack_begin, _obstack_newchunk, obstack_free). Every program linking
# libgit.a links it.
fb=$(LC_ALL=C nm -A --defined-only "$REF/git/libgit.a" 2>/dev/null | awk -F: '{ print $2 }' | LC_ALL=C sort -u > "$W/git-def.list"
     LC_ALL=C ar t "$REF/git/libgit.a" | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$W/git-def.list" |
     while read -r m; do
       u=$(awk -v m="$m" '$1 ~ "^git/" { b = $1; sub(/.*\//, "", b); if (b == m) print $1 }' "$R/units")
       [ "$(echo "$u" | grep -c .)" = 1 ] || { echo "record: libgit.a member $m: no single unit" >&2; exit 1; }
       src=$(awk -v o="$u" '$1 == o { print $2 "/" $3 }' "$R/units")
       grep -qE '__GNU_LIBRARY__|__GLIBC__' "$REF/$src" && echo "$u"
     done)
rm -f "$W/git-def.list"
[ -n "$fb" ] && echo "record: glibc-elided fallbacks linked: $(echo $fb)"
awk -v fb="$(echo $fb)" '{ print $0 (fb == "" ? "" : " " fb) }' "$R/link" > "$R/link.new"
mv "$R/link.new" "$R/link"
# the stage's headers: zlib's are in zlib/, mbedTLS's in mbedtls/include,
# relative to each unit's directory (git/ is one level down, curl/lib two)
awk -v s="$S/include" -v c="$REF/curl/include" '
  { d = $2; p = "../"; while (sub(/\//, "", d)) p = p "../"
    for (i = 4; i <= NF; i++) {
      if ($i == "-I" s) $i = "-I" p "mbedtls/include -I" p "zlib"
      else if ($i == s) $i = p "mbedtls/include"
      else if ($i == "-I" c) $i = "-I" p "curl/include"
    }
    print }' "$R/units" > "$R/units.new"
mv "$R/units.new" "$R/units"
grep -q "$REF" "$R/units" "$R/link" && { grep -m3 "$REF" "$R/units" "$R/link" >&2; echo "record: a host path is left in the recipe" >&2; exit 1; }

# the generated sources: .c/.h in the built trees that the tarballs lack,
# plus git's version (GIT-VERSION-FILE feeds -D flags already in `units`)
: > "$R/generated.list"
for t in zlib:"$ZLIB":xz mbedtls:"$MBED":bz2 curl:"$CURL":xz git:"$GIT":xz; do
  d=${t%%:*}; rest=${t#*:}; tb=${rest%:*}; z=${rest##*:}
  if [ "$z" = bz2 ]; then bzcat "$W/dl/$tb"; else xzcat "$W/dl/$tb"; fi | tar -tf - \
    | sed "s|^[^/]*/|$d/|" | LC_ALL=C sort > "$W/git-upstream.list"
  ( cd "$REF" && find "$d" -type f \( -name '*.c' -o -name '*.h' \) ) | LC_ALL=C sort \
    | LC_ALL=C comm -23 - "$W/git-upstream.list" >> "$R/generated.list"
done
# zlib's configure rewrites zconf.h in place (it is in the tarball)
echo zlib/zconf.h >> "$R/generated.list"
rm -f "$W/git-upstream.list"
( cd "$REF" && tar -cf "$R/gen.tar" -T "$R/generated.list" git/templates/blt )
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units; $(awk '{ printf "%s links %d objects; ", $1, NF - 1 }' "$R/link"))"

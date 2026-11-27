#!/bin/sh
# record.sh: write the curl recipe -- curl with mbedTLS for HTTPS, and the
# Mozilla CA bundle -- that onsite.sh replays on the target.
#
# HOST SIDE, the only step that needs gcc. Two source trees in one recipe:
#   mbedtls/  mbedTLS 3.6 (LTS). Its Makefile is .SILENT, so the units come
#             from a dry run (`make -n -B`), which prints every command.
#             Built and staged (make install) so curl's configure finds it.
#   curl/     curl's autoconf configure + libtool make, against that stage.
# What they decided travels in the recipe, PRE-GENERATED:
#   gen.tar   mbedtls_config.h (as shipped: AES-NI on), curl/lib/curl_config.h,
#             curl/src/tool_ca_embed.c
#   units     one line per object, paths relative to the recipe's tree root
#             (../lib/units-from-make.sh); the stage's include directory is
#             rewritten to mbedtls/include, relative to each unit
#   link      `curl` and its objects: the tool's own, then the libcurl and
#             mbedTLS archive members gcc's linker pulled (a -Wl,-Map map),
#             because pxx --link takes objects, not archives
#   cacert.pem  the pinned Mozilla CA bundle, installed as
#             /etc/ssl/certs/ca-certificates.crt, which curl is built to read
# The configure choices, given rather than probed: static, mbedTLS, the CA
# bundle path, no CA directory; HTTP(S), FTP(S), FILE and WS(S) only (no LDAP,
# RTSP, DICT, TELNET, TFTP, POP3, IMAP, SMB, SMTP, GOPHER, MQTT); and none of
# zlib, brotli, zstd, nghttp2/3, ngtcp2, libidn2, libpsl, libssh(2), librtmp,
# gsasl, which do not exist on site. The threaded resolver stays (pthreads,
# hence --threadsafe on every unit).
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/curl/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
MBED=mbedtls-3.6.8.tar.bz2
CURL=curl-8.23.0.tar.xz
CA=cacert-2026-11-05.pem
"$T/../fetch.sh" "$MBED" "$CURL" "$CA" > /dev/null
REF=$W/curl-ref
R=$W/recipe/curl
rm -rf "$REF" "$R"
mkdir -p "$REF/mbedtls" "$REF/curl" "$REF/stage" "$R"
bzcat "$W/dl/$MBED" | tar -xf - -C "$REF/mbedtls" --strip-components=1
xzcat "$W/dl/$CURL" | tar -xf - -C "$REF/curl" --strip-components=1
# AES-NI on, as mbedTLS ships: aesni.c's inline-asm path (gcc without -maes
# takes it: movdqu, pxor, pshufd, the AES-NI and PCLMULQDQ instructions as
# .byte, a `call` inside the template), which pxx encodes as gas does
# (feature-c-inline-asm-sse-and-aes-ni). mbedTLS picks AES-NI at run time
# when the CPU has it and its software AES otherwise. The header travels in
# gen.tar unedited; the check keeps a future mbedTLS from dropping it.
MCFG=$REF/mbedtls/include/mbedtls/mbedtls_config.h
grep -q '^#define MBEDTLS_AESNI_C$' "$MCFG" || { echo "record: MBEDTLS_AESNI_C not where expected" >&2; exit 1; }

# mbedTLS: the commands from a dry run, then the real build and the stage
make -C "$REF/mbedtls/library" -n -B CC=gcc static > "$W/curl-mbedtls-dry.log" 2>&1
make -C "$REF/mbedtls/library" -j3 CC=gcc static > "$W/curl-mbedtls-build.log" 2>&1
make -C "$REF/mbedtls" install DESTDIR="$REF/stage" > /dev/null 2>&1
S=$REF/stage

cd "$REF/curl"
CC=gcc ./configure --with-mbedtls="$S" --disable-shared --enable-static \
  --without-libpsl --without-zlib --without-brotli --without-zstd \
  --without-nghttp2 --without-nghttp3 --without-ngtcp2 --without-libidn2 \
  --without-libssh2 --without-libssh --without-librtmp --without-libgsasl \
  --disable-ldap --disable-ldaps --disable-rtsp --disable-dict --disable-telnet \
  --disable-tftp --disable-pop3 --disable-imap --disable-smb --disable-smtp \
  --disable-gopher --disable-mqtt --disable-manual --without-ca-path \
  --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt > "$W/curl-configure.log" 2>&1
make -j1 V=1 > "$W/curl-build.log" 2>&1
[ -x src/curl ] || { echo "record: gcc build made no curl" >&2; exit 1; }
# relink with a map: which archive members curl pulls
rm -f src/curl
make -C src V=1 curl LDFLAGS="-Wl,-Map=$W/curl.map" > "$W/curl-relink.log" 2>&1
[ -x src/curl ] || { echo "record: relinking curl with a map failed" >&2; exit 1; }

for f in "$MBED" "$CURL" "$CA"; do
  echo "$f $(sha256sum "$W/dl/$f" | cut -d' ' -f1)"
done > "$R/sources.list"

# units: mbedTLS (no program links in its log) and curl, one tree root
sh "$T/../lib/units-from-make.sh" "$REF" "$W/curl-mbedtls-dry.log" | awk '/^%%$/ { exit } { print }' > "$R/units"
sh "$T/../lib/units-from-make.sh" "$REF" "$W/curl-build.log" curl > "$W/curl-units.txt"
awk '/^%%$/ { exit } { print }' "$W/curl-units.txt" >> "$R/units"
# the stage's headers are mbedtls/include: every curl unit is two levels down
sed -i "s|-I$S/include|-I../../mbedtls/include|g" "$R/units"

own=$(awk '/^%%$/ { s = 1; next } s && $1 == "curl" { for (i = 2; i <= NF; i++) if ($i ~ /^curl\/src\//) printf " %s", $i }' "$W/curl-units.txt")
members=$(grep -oE '(libcurl|libmbedtls|libmbedx509|libmbedcrypto)\.a\([^)]*\.o\)' "$W/curl.map" | sort -u |
  awk -v units="$R/units" '
    BEGIN { while ((getline l < units) > 0) { split(l, f, " "); o = f[1]; n = o; sub(/.*\//, "", n)
              top = (o ~ /^mbedtls\//) ? "mbed" : (o ~ /^curl\/lib\// ? "curl" : "")
              if (top == "") continue; key[top "/" n] = key[top "/" n] " " o; cnt[top "/" n]++ } }
    { lib = $0; sub(/\.a\(.*/, "", lib); m = $0; sub(/.*\(/, "", m); sub(/\)$/, "", m)
      k = (lib == "libcurl" ? "curl" : "mbed") "/" m
      if (cnt[k] != 1) { print "record: archive member " $0 " matches " cnt[k] + 0 " units" > "/dev/stderr"; exit 1 }
      printf "%s", key[k] }')
echo "curl$own$members" > "$R/link"
grep -q "$REF" "$R/units" "$R/link" && { grep -m3 "$REF" "$R/units" >&2; echo "record: a host path is left in the recipe" >&2; exit 1; }
( cd "$REF" && tar -cf "$R/gen.tar" mbedtls/include/mbedtls/mbedtls_config.h curl/lib/curl_config.h curl/src/tool_ca_embed.c )
cp "$W/dl/$CA" "$R/cacert.pem"
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
set -- $(cut -d' ' -f2- "$R/link")
echo "recipe: $R ($(wc -l < "$R/units") units recorded; curl links $# objects)"

#!/bin/sh
# test.sh: build dhcpcd with onsite.sh (pxx only) and compare it with the gcc
# build record.sh left in $NODISX_WORK/dhcpcd-ref, on what runs without root:
#   1. --version and the usage text
#   2. -V, the whole option-definition table (dhcpcd-embedded.c parsed at
#      start-up and printed), with the shipped dhcpcd.conf and with a config of
#      `define`/`define6`/`vendopt`/`embed` blocks that drives the option parser
#   3. dhcpcd's own crypto self-test (tests/crypt: the RFC 2202 HMAC-MD5 and
#      FIPS 180-2 SHA-256 vectors), its sources and compat/crypt built by pxx;
#      it checks the digests itself, and its output is compared with gcc's
# A live lease (DISCOVER..ACK) needs a network namespace or a VM: this host
# refuses unprivileged user namespaces, so that is left to the Path B QEMU
# image, whose user-mode network answers DHCP.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/dhcpcd/test.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$T/../../../compiler/pascal26}
REF=$W/dhcpcd-ref
R=$W/recipe/dhcpcd
[ -x "$REF/src/dhcpcd" ] && [ -f "$R/units" ] || { echo "test: run record.sh first" >&2; exit 1; }
O=$(mktemp -d -p "$W" dhcpcd-test.XXXXXX)
DL=$W/dl PXX=$PXX JOBS=${JOBS:-4} RECIPE=$R sh "$R/onsite.sh" "$O/work" > "$O/onsite.log" 2>&1 \
  || { tail -5 "$O/onsite.log" >&2; echo "test: FAIL (on-site build)" >&2; exit 1; }
G=$REF/src/dhcpcd
P=$O/work/dhcpcd
fail=0

# compare NAME CMD... : run CMD with $D (the dhcpcd under test) set to the gcc
# build, then to the pxx one; the outputs (exit status included) must match
compare() {
  name=$1; shift
  # (a failing command must not end the set -e subshell: its status is data)
  g=$(D=$G; rc=0; eval "$*" 2>&1 || rc=$?; echo "rc=$rc")
  p=$(D=$P; rc=0; eval "$*" 2>&1 || rc=$?; echo "rc=$rc")
  # the program's own path (argv[0] in messages) is not a difference
  g=$(printf '%s\n' "$g" | sed "s|$G|PROG|g")
  p=$(printf '%s\n' "$p" | sed "s|$P|PROG|g")
  if [ "$g" = "$p" ]; then
    echo "same    $name ($(printf '%s\n' "$g" | wc -l) lines)"
  else
    echo "DIFFERS $name"
    printf '%s\n' "$g" > "$O/$name.gcc"
    printf '%s\n' "$p" > "$O/$name.pxx"
    diff "$O/$name.gcc" "$O/$name.pxx" | head -10
    fail=1
  fi
}

cat > "$O/defs.conf" <<'EOF'
define 224 string site_name
define 225 array ipaddress site_servers
define 226 embed site_pair
embed uint16 code
embed string label
define6 200 uint32 v6_counter
define6 201 domain v6_search
vendopt 4242 encap acme
encap 1 string acme_model
encap 2 uint8 acme_rev
nohook resolv.conf
option site_name, site_servers
EOF

compare version '"$D" --version'
compare usage '"$D" --help'
compare optiontable '"$D" -f /dev/null -V'
compare optiontable-shipped '"$D" -f "$REF/src/dhcpcd.conf" -V'
compare optiontable-defines '"$D" -f "$O/defs.conf" -V'
compare bad-option '"$D" --no-such-option'

# the crypto self-test, against the same flags the units were built with
flags=$(grep '^compat/crypt/md5.o ' "$R/units" | cut -d' ' -f4- | tr ' ' '\n' | grep '^-D' | tr '\n' ' ')
mkdir -p "$O/crypt"
for s in run-test test_hmac_md5 test_sha256; do
  ( cd "$O/work/src/tests/crypt" &&
    # shellcheck disable=SC2086
    "$PXX" --emit-obj --function-sections --shared-runtime $flags -I../.. -I../../src \
      "$s.c" "$O/crypt/$s.o" > "$O/crypt/$s.log" 2>&1 ) \
    || { grep -m1 error "$O/crypt/$s.log" >&2; echo "test: FAIL (crypt test $s.c)" >&2; exit 1; }
done
"$PXX" --link -o "$O/crypt/run-test" "$O/crypt/run-test.o" "$O/crypt/test_hmac_md5.o" \
  "$O/crypt/test_sha256.o" "$O/work/obj/compat_crypt_hmac.o" "$O/work/obj/compat_crypt_md5.o" \
  "$O/work/obj/compat_crypt_sha256.o" > "$O/crypt/link.log" 2>&1 \
  || { tail -3 "$O/crypt/link.log" >&2; echo "test: FAIL (crypt link)" >&2; exit 1; }
[ -x "$REF/tests/crypt/run-test" ] || make -C "$REF/tests/crypt" > /dev/null 2>&1
G=$REF/tests/crypt/run-test
P=$O/crypt/run-test
compare crypt-selftest '"$D"'

if [ "$fail" = 0 ]; then echo "test: PASS ($O)"; else echo "test: FAIL ($O)"; exit 1; fi

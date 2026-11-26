#!/bin/sh
# test.sh: build dropbear with onsite.sh (pxx only), then run the proof of
# tools/dropbear_pxx.py on those four binaries, and the same proof on the gcc
# build record.sh left (the oracle: a row that fails there is the test's, not
# pxx's). On 127.0.0.1, unprivileged ports, throwaway keys; ~/.ssh untouched:
#   - dropbearkey makes ed25519/ecdsa/rsa host keys that ssh-keygen reads
#   - stock OpenSSH logs in to the pxx dropbear by key, once per cipher, MAC,
#     key exchange (incl. sntrup761 and ML-KEM hybrids) and host-key type
#   - 1 MiB each way through the channel, an interactive pty session
#   - scp both ways with the stock client, and with the pxx scp as client
#   - the pxx dbclient logs in to a stock sshd, once per cipher
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/dropbear/test.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$T/../../../compiler/pascal26}
REF=$W/dropbear-ref
R=$W/recipe/dropbear
[ -x "$REF/dropbear" ] && [ -f "$R/units" ] || { echo "test: run record.sh first" >&2; exit 1; }
O=$(mktemp -d -p "$W" dropbear-test.XXXXXX)
DL=$W/dl PXX=$PXX JOBS=${JOBS:-4} RECIPE=$R sh "$R/onsite.sh" "$O/work" > "$O/onsite.log" 2>&1 \
  || { tail -5 "$O/onsite.log" >&2; echo "test: FAIL (on-site build)" >&2; exit 1; }
fail=0
for b in gcc:"$REF" pxx:"$O/work"; do
  name=${b%%:*}; dir=${b#*:}
  python3 "$T/../../dropbear_pxx.py" --bindir "$dir" > "$O/proof-$name.log" 2>&1 || :
  last=$(tail -1 "$O/proof-$name.log")
  rows=$(grep -o '[0-9]* rows, [0-9]* failed' "$O/proof-$name.log" || echo 'no result')
  echo "$name build: $rows; $last"
  case $last in
    "DROPBEAR-PXX-COMPLETE GREEN") ;;
    *) fail=1; grep 'FAIL' "$O/proof-$name.log" | head -5 ;;
  esac
done
if [ "$fail" = 0 ]; then echo "test: PASS ($O)"; else echo "test: FAIL ($O)"; exit 1; fi

#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# urllib_https_devtest.sh -- a NilPy program's urlopen("https://...") with no
# TLS backend registered by the program: mimic_urllib_request installs the
# native TLS 1.3 backend itself (owner, 2026-10-05). Hermetic but needs the
# openssl CLI, so opt-in (`make urllib-https-devtest`), like the other TLS
# devtests; skips cleanly without openssl.
#
# Rows: a trusted chain answers 200 (with and without a timeout); a CA the
# trust file does not hold, and a hostname the leaf does not name, are
# refused with a URLError carrying the handshake's reason. truststore checks
# the host inside VerifyServerChain, so a mismatch reads "certificate chain
# does not verify to a trusted root" as well -- true, not specific.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PXX=${PXX:-"$ROOT/compiler/pascal26"}
D=$(mktemp -d /tmp/pxx_urlhttps.XXXXXX)
SRV_PID=""
fail=0
say() { printf '%s\n' "$*"; }
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$D"; }
trap cleanup EXIT INT TERM

say "=== urllib-https-devtest (urlopen over the native TLS 1.3 backend) ==="
command -v openssl >/dev/null 2>&1 || { say "SKIP: no openssl CLI"; exit 0; }
if ! "$PXX" "$ROOT/test/lib_mimic_urllib_request_https.npy" "$D/client" >"$D/build.log" 2>&1; then
  say "FAIL: client build"; tail -3 "$D/build.log"; exit 1
fi

printf 'subjectAltName=DNS:localhost\n' > "$D/ext"
mint() {   # $1 = name
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -keyout "$D/$1.cakey" \
    -out "$D/$1.ca" -days 1 -nodes -subj "/CN=PXX urllib CA $1" >/dev/null 2>&1 &&
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -keyout "$D/$1.key" \
    -out "$D/$1.csr" -nodes -subj "/CN=localhost" >/dev/null 2>&1 &&
  openssl x509 -req -in "$D/$1.csr" -CA "$D/$1.ca" -CAkey "$D/$1.cakey" \
    -CAcreateserial -days 1 -extfile "$D/ext" -out "$D/$1.leaf" >/dev/null 2>&1
}
mint good && mint other || { say "INCONCLUSIVE: openssl could not mint the chain"; exit 2; }

PORT=$((20000 + RANDOM % 20000))
openssl s_server -accept "$PORT" -cert "$D/good.leaf" -key "$D/good.key" \
  -tls1_3 -www -quiet >/dev/null 2>&1 &
SRV_PID=$!
i=0; while [ $i -lt 50 ]; do
  openssl s_client -connect "127.0.0.1:$PORT" -tls1_3 </dev/null >/dev/null 2>&1 && break
  i=$((i+1)); sleep 0.1
done

row() {   # $1 = name, $2 = trust file, $3 = url, $4 = grep for, [$5 = timeout]
  out=$(SSL_CERT_FILE="$2" timeout 40 "$D/client" "$3" ${5:+"$5"} 2>&1)
  if printf '%s' "$out" | grep -q -- "$4"; then
    say "OK    $1"; printf "%s\n" "$out" | tail -1 | sed "s/^/      /"
  else
    say "FAIL  $1 (wanted '$4')"; printf '%s\n' "$out" | sed 's/^/      /'; fail=1
  fi
}
row "trusted chain"             "$D/good.ca"  "https://localhost:$PORT/" "^HTTPS OK"
row "trusted chain, timeout=5"  "$D/good.ca"  "https://localhost:$PORT/" "^HTTPS OK" 5
row "untrusted root refused"    "$D/other.ca" "https://localhost:$PORT/" "^URLError TLS: "
row "hostname mismatch refused" "$D/good.ca"  "https://127.0.0.1:$PORT/" "^URLError TLS: "

if [ $fail -ne 0 ]; then say "urllib-https-devtest: RED"; exit 1; fi
say "urllib-https-devtest: GREEN"

#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# The NATIVE TLS 1.3 backend driven through the tls.pas seam
# (feature-tls-provider-abstraction slice 2).
#
# The client (test/devtest_tls_native_seam.pas) calls only TlsHandshake /
# TlsWrite / TlsRead / TlsClose -- it names no tls13_* unit beyond the `uses`
# that registers the backend. So this asserts the thing that matters: an
# https:// caller can reach the from-scratch stack.
#
# Positive runs cover all three server signature schemes. The NEGATIVE runs
# carry as much weight: a TLS client that accepts everything passes every
# positive test, and the failures below are the ones that make trust mean
# anything -- an untrusted root, a hostname mismatch, and a trust file that is
# empty or missing.
#
# Non-hermetic (needs the openssl CLI); skips cleanly when absent. NOT in the
# lib-test gate.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PXX_STABLE=${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}
CLIENT=/tmp/pxx_devtest_tls_native_seam
D=/tmp/pxx_seam
SRV_PID=""
fail=0

say() { printf '%s\n' "$*"; }
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -f "$D".*; }
trap cleanup EXIT INT TERM

say "=== tls-native-seam-devtest (native TLS 1.3 through the tls.pas seam) ==="

command -v openssl >/dev/null 2>&1 || { say "SKIP: no openssl CLI"; exit 0; }

if ! "$PXX_STABLE" -Fu"$ROOT/lib/rtl" -Fu"$ROOT/lib/rtl/platform/posix" \
      "$ROOT/test/devtest_tls_native_seam.pas" "$CLIENT" >/tmp/pxx_seam_build.log 2>&1; then
  say "FAIL: client build"; tail -3 /tmp/pxx_seam_build.log; exit 1
fi

printf 'subjectAltName=DNS:localhost\n' > "$D.ext"

# mint a self-signed root + a localhost leaf signed by it, with $1 key args
mint() {
  nm=$1; keyargs=$2
  # shellcheck disable=SC2086
  openssl req -x509 $keyargs -keyout "$D.$nm.cakey" -out "$D.$nm.ca" -days 1 -nodes \
    -subj "/CN=PXX Seam CA $nm" >/dev/null 2>&1 || return 1
  # shellcheck disable=SC2086
  openssl req $keyargs -keyout "$D.$nm.key" -out "$D.$nm.csr" -nodes \
    -subj "/CN=localhost" >/dev/null 2>&1 || return 1
  openssl x509 -req -in "$D.$nm.csr" -CA "$D.$nm.ca" -CAkey "$D.$nm.cakey" \
    -CAcreateserial -days 1 -extfile "$D.ext" -out "$D.$nm.leaf" >/dev/null 2>&1 || return 1
  return 0
}

serve() {
  openssl s_server -accept "$1" -cert "$2" -key "$3" -tls1_3 -www -quiet >/dev/null 2>&1 &
  SRV_PID=$!
  i=0; while [ $i -lt 50 ]; do
    openssl s_client -connect "127.0.0.1:$1" -tls1_3 </dev/null >/dev/null 2>&1 && break
    i=$((i+1)); sleep 0.1
  done
}

# expect_ok <name> <port> <leaf> <key> <ca-file> <host>
expect_ok() {
  serve "$2" "$3" "$4"
  out=$(SSL_CERT_FILE="$5" timeout 40 "$CLIENT" "$2" "$6" 2>&1)
  kill "$SRV_PID" 2>/dev/null; SRV_PID=""
  if printf '%s' "$out" | grep -q '^SEAM OK'; then
    say "OK    $1"
  else
    say "FAIL  $1"; printf '%s\n' "$out" | sed 's/^/      /'; fail=1
  fi
}

# expect_refused <name> <port> <leaf> <key> <ca-file> <host>
expect_refused() {
  serve "$2" "$3" "$4"
  out=$(SSL_CERT_FILE="$5" timeout 40 "$CLIENT" "$2" "$6" 2>&1)
  kill "$SRV_PID" 2>/dev/null; SRV_PID=""
  if printf '%s' "$out" | grep -q '^handshake=FAIL'; then
    say "OK    $1 (refused: $(printf '%s' "$out" | grep '^handshake=FAIL' | cut -c17-72))"
  else
    say "FAIL  $1 -- the handshake was ACCEPTED and should not have been"
    printf '%s\n' "$out" | sed 's/^/      /'; fail=1
  fi
}

mint rsa "-newkey rsa:2048"                                  || { say "SKIP: rsa keygen"; exit 0; }
mint ed  "-newkey ed25519"                                   || { say "SKIP: ed keygen";  exit 0; }
mint ec  "-newkey ec -pkeyopt ec_paramgen_curve:P-256"       || { say "SKIP: ec keygen";  exit 0; }

expect_ok "rsa_pss server"   28821 "$D.rsa.leaf" "$D.rsa.key" "$D.rsa.ca" localhost
expect_ok "ed25519 server"   28822 "$D.ed.leaf"  "$D.ed.key"  "$D.ed.ca"  localhost
expect_ok "ecdsa_p256 server" 28823 "$D.ec.leaf" "$D.ec.key"  "$D.ec.ca"  localhost

# the chain must actually be anchored, and the name must actually match
expect_refused "untrusted root"    28824 "$D.rsa.leaf" "$D.rsa.key" "$D.ed.ca"  localhost
expect_refused "hostname mismatch" 28825 "$D.rsa.leaf" "$D.rsa.key" "$D.rsa.ca" evil.test
expect_refused "empty trust file"  28826 "$D.rsa.leaf" "$D.rsa.key" /dev/null   localhost
expect_refused "missing trust file" 28827 "$D.rsa.leaf" "$D.rsa.key" "$D.nope"  localhost

# The whole chain: HttpGet over https:// -> tls.pas seam -> native backend.
# The seam runs above prove the backend; this proves an ordinary caller reaches
# it through http.pas without naming a TLS unit beyond the registrar.
HTTPSCLI=/tmp/pxx_devtest_https_native
if "$PXX_STABLE" -Fu"$ROOT/lib/rtl" -Fu"$ROOT/lib/rtl/platform/posix" \
      "$ROOT/test/devtest_https_native.pas" "$HTTPSCLI" >/tmp/pxx_https_build.log 2>&1; then
  serve 28828 "$D.rsa.leaf" "$D.rsa.key"
  out=$(SSL_CERT_FILE="$D.rsa.ca" timeout 40 "$HTTPSCLI" "https://localhost:28828/" 2>&1)
  kill "$SRV_PID" 2>/dev/null; SRV_PID=""
  if printf '%s' "$out" | grep -q '^HTTPS OK'; then
    say "OK    HttpGet over https (no libssl in the process)"
  else
    say "FAIL  HttpGet over https"; printf '%s\n' "$out" | sed 's/^/      /'; fail=1
  fi
else
  say "FAIL  https client build"; tail -3 /tmp/pxx_https_build.log; fail=1
fi

if [ "$fail" -eq 0 ]; then
  say "tls-native-seam-devtest OK (3 schemes, 4 refusals, https via http.pas)"
  exit 0
fi
say "tls-native-seam-devtest FAILED"
exit 1

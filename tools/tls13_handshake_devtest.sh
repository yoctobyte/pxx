#!/bin/sh
# From-scratch TLS 1.3 client handshake against a loopback `openssl s_server
# -tls1_3`: ClientHello -> ServerHello -> X25519 ECDHE -> key schedule -> decrypt
# the server flight -> verify CertificateVerify + the cert CHAIN (leaf <- trusted
# CA, validity, hostname) + the server Finished -> client Finished -> app keys ->
# HTTP GET -> decrypt the response. Runs both the kTLS-TX offload (if the `tls`
# module is loaded) and the forced Pascal-record-layer fallback.
#
# Non-hermetic (needs the openssl CLI); skips cleanly when absent. NOT in the
# lib-test gate.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PXX_STABLE=${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}
PORT=28794
CAKEY=/tmp/pxx_tls13_ca.key
CAPEM=/tmp/pxx_tls13_ca.pem
LKEY=/tmp/pxx_tls13_leaf.key
LCSR=/tmp/pxx_tls13_leaf.csr
LPEM=/tmp/pxx_tls13_leaf.pem
EXT=/tmp/pxx_tls13_ext.cnf
CLIENT=/tmp/pxx_devtest_tls13_handshake
SLOG=/tmp/pxx_tls13_sserver.log
SRV_PID=""

say() { printf '%s\n' "$*"; }
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -f "$CAKEY" "$CAPEM" "$LKEY" "$LCSR" "$LPEM" "$EXT" "$CADER"; }
trap cleanup EXIT INT TERM

[ -x "$PXX_STABLE" ] || { say "SKIP: no pinned compiler"; exit 0; }
command -v openssl >/dev/null 2>&1 || { say "SKIP: openssl CLI not found"; exit 0; }

say "=== tls13-handshake-devtest (from-scratch TLS 1.3 client: handshake + chain verify + GET) ==="

if ! "$PXX_STABLE" -Fu"$ROOT/lib/rtl/platform/posix" \
      "$ROOT/test/devtest_tls13_handshake.pas" "$CLIENT" >/tmp/pxx_tls13_build.log 2>&1; then
  say "FAIL: client build"; tail -3 /tmp/pxx_tls13_build.log; exit 1
fi

# root CA + leaf (SAN=localhost) signed by the CA, all ed25519
openssl req -x509 -newkey ed25519 -keyout "$CAKEY" -out "$CAPEM" -days 1 -nodes \
  -subj "/CN=PXX Test Root CA" >/dev/null 2>&1 || { say "SKIP: CA gen failed"; exit 0; }
openssl req -newkey ed25519 -keyout "$LKEY" -out "$LCSR" -nodes \
  -subj "/CN=localhost" >/dev/null 2>&1 || { say "SKIP: leaf csr failed"; exit 0; }
printf 'subjectAltName=DNS:localhost\n' > "$EXT"
openssl x509 -req -in "$LCSR" -CA "$CAPEM" -CAkey "$CAKEY" -CAcreateserial -days 1 \
  -extfile "$EXT" -out "$LPEM" >/dev/null 2>&1 || { say "SKIP: leaf sign failed"; exit 0; }

# the trust anchor (CA) handed to the client as a DER file path, plus the UTC time
CADER=/tmp/pxx_tls13_ca.der
openssl x509 -in "$CAPEM" -outform DER -out "$CADER" 2>/dev/null
NOW=$(date -u +%Y%m%d%H%M%S)

start_server() {
  openssl s_server -accept "$PORT" -cert "$LPEM" -key "$LKEY" -tls1_3 -www -quiet >"$SLOG" 2>&1 &
  SRV_PID=$!
  i=0; while [ $i -lt 50 ]; do openssl s_client -connect "127.0.0.1:$PORT" -tls1_3 </dev/null >/dev/null 2>&1 && break; i=$((i+1)); sleep 0.1; done
}

start_server
say "--- run 1: default (kTLS TX if the tls module is loaded) ---"
OUT=$(timeout 30 "$CLIENT" "$PORT" "$CADER" "$NOW" 2>&1); RC=$?
say "$OUT"
PASS1=0; [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q '^ALL OK' && printf '%s' "$OUT" | grep -q 'chain-verified=ok' && PASS1=1

kill "$SRV_PID" 2>/dev/null; SRV_PID=""
start_server
say "--- run 2: forced fallback (no-ktls, Pascal record layer) ---"
OUT2=$(timeout 30 "$CLIENT" "$PORT" "$CADER" "$NOW" no-ktls 2>&1); RC2=$?
say "$OUT2"
PASS2=0; [ $RC2 -eq 0 ] && printf '%s' "$OUT2" | grep -q '^ALL OK' && printf '%s' "$OUT2" | grep -q 'chain-verified=ok' && PASS2=1

if [ $PASS1 -eq 1 ] && [ $PASS2 -eq 1 ]; then
  say "tls13-handshake-devtest OK (handshake + chain verify + kTLS-TX + Pascal fallback)"
  exit 0
else
  say "FAIL: run1=$PASS1 run2=$PASS2"
  exit 1
fi

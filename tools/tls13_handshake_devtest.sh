#!/bin/sh
# From-scratch TLS 1.3 client handshake (phase 1) against a loopback
# `openssl s_server -tls1_3`: ClientHello -> ServerHello -> X25519 ECDHE ->
# handshake key schedule -> decrypt the server's first encrypted flight.
# Proves the M1-M6 units interoperate with a real TLS 1.3 server.
#
# Non-hermetic (needs the openssl CLI); skips cleanly when absent. NOT in the
# lib-test gate.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PXX_STABLE=${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}
PORT=28794
CERT=/tmp/pxx_tls13_cert.pem
KEY=/tmp/pxx_tls13_key.pem
CLIENT=/tmp/pxx_devtest_tls13_handshake
SLOG=/tmp/pxx_tls13_sserver.log
SRV_PID=""

say() { printf '%s\n' "$*"; }
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -f "$CERT" "$KEY"; }
trap cleanup EXIT INT TERM

[ -x "$PXX_STABLE" ] || { say "SKIP: no pinned compiler"; exit 0; }
command -v openssl >/dev/null 2>&1 || { say "SKIP: openssl CLI not found"; exit 0; }

say "=== tls13-handshake-devtest (from-scratch TLS 1.3 client, phase 1) ==="

if ! "$PXX_STABLE" -Fu"$ROOT/lib/rtl/platform/posix" \
      "$ROOT/test/devtest_tls13_handshake.pas" "$CLIENT" >/tmp/pxx_tls13_build.log 2>&1; then
  say "FAIL: client build"; tail -3 /tmp/pxx_tls13_build.log; exit 1
fi

openssl req -x509 -newkey ed25519 -keyout "$KEY" -out "$CERT" -days 1 -nodes \
  -subj "/CN=localhost" >/dev/null 2>&1 || { say "SKIP: cert gen failed"; exit 0; }
openssl s_server -accept "$PORT" -cert "$CERT" -key "$KEY" -tls1_3 -www -quiet >"$SLOG" 2>&1 &
SRV_PID=$!

i=0
while [ $i -lt 50 ]; do
  openssl s_client -connect "127.0.0.1:$PORT" -tls1_3 </dev/null >/dev/null 2>&1 && break
  i=$((i + 1)); sleep 0.1
done

OUT=$(timeout 30 "$CLIENT" "$PORT" 2>&1)
RC=$?
say "$OUT"
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q '^ALL OK'; then
  say "tls13-handshake-devtest OK (real TLS 1.3 key exchange + flight decryption)"
  exit 0
else
  say "FAIL: client rc=$RC"
  exit 1
fi

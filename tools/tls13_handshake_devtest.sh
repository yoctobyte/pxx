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

say "=== tls13-handshake-devtest (from-scratch TLS 1.3 client, full handshake + GET + kTLS-TX) ==="

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

# run twice: default (kTLS offload if module loaded) + forced Pascal fallback
say "--- run 1: default (kTLS TX if the tls module is loaded) ---"
OUT=$(timeout 30 "$CLIENT" "$PORT" 2>&1); RC=$?
say "$OUT"
PASS1=0; [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q '^ALL OK' && PASS1=1

# restart the server for a fresh connection
kill "$SRV_PID" 2>/dev/null
openssl s_server -accept "$PORT" -cert "$CERT" -key "$KEY" -tls1_3 -www -quiet >"$SLOG" 2>&1 &
SRV_PID=$!
i=0; while [ $i -lt 50 ]; do openssl s_client -connect "127.0.0.1:$PORT" -tls1_3 </dev/null >/dev/null 2>&1 && break; i=$((i+1)); sleep 0.1; done

say "--- run 2: forced fallback (no-ktls, Pascal record layer) ---"
OUT2=$(timeout 30 "$CLIENT" "$PORT" no-ktls 2>&1); RC2=$?
say "$OUT2"
PASS2=0; [ $RC2 -eq 0 ] && printf '%s' "$OUT2" | grep -q '^ALL OK' && PASS2=1

if [ $PASS1 -eq 1 ] && [ $PASS2 -eq 1 ]; then
  say "tls13-handshake-devtest OK (full handshake + kTLS TX offload + Pascal fallback)"
  exit 0
else
  say "FAIL: run1=$PASS1 run2=$PASS2"
  exit 1
fi

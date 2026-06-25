#!/bin/sh
# Real-HTTPS devtest for the OpenSSL TLS backend (feature-tls-provider-abstraction).
# Builds the client with the dlopen loader (-dPXX_DYNLIB_LIBC) and runs a blocking
# HttpGet over https against a loopback `openssl s_server -www`.
#
# NOT in the hermetic lib-test gate (needs the openssl CLI + libssl.so.3). Skips
# cleanly (exit 0) when prereqs are absent; exits non-zero only on a genuine
# failure when prereqs ARE present.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PXX_STABLE=${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}
PORT=28771
CERT=/tmp/pxx_tls_devtest_cert.pem
KEY=/tmp/pxx_tls_devtest_key.pem
SLOG=/tmp/pxx_tls_devtest_sserver.log
CLIENT=/tmp/pxx_devtest_tls_openssl
SRV_PID=""

say() { printf '%s\n' "$*"; }

cleanup() {
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  rm -f "$CERT" "$KEY"
}
trap cleanup EXIT INT TERM

# ---- prereqs ----
if [ ! -x "$PXX_STABLE" ]; then
  say "SKIP: missing pinned stable compiler: $PXX_STABLE"; exit 0
fi
if ! command -v openssl >/dev/null 2>&1; then
  say "SKIP: openssl CLI not found"; exit 0
fi
if ! ls /lib/*/libssl.so.3 /usr/lib/*/libssl.so.3 >/dev/null 2>&1; then
  say "SKIP: libssl.so.3 not found"; exit 0
fi

say "=== tls-openssl-devtest (real HTTPS via dlopen'd libssl) ==="

# ---- build the client (needs the real loader) ----
if ! "$PXX_STABLE" -dPXX_DYNLIB_LIBC -Fu"$ROOT/lib/rtl/platform/posix" \
      "$ROOT/test/devtest_tls_openssl.pas" "$CLIENT" >/tmp/pxx_tls_devtest_build.log 2>&1; then
  say "FAIL: client build"; tail -3 /tmp/pxx_tls_devtest_build.log; exit 1
fi

# ---- self-signed cert + loopback TLS server ----
if ! openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" \
      -days 1 -nodes -subj "/CN=localhost" >/dev/null 2>&1; then
  say "SKIP: cert generation failed"; exit 0
fi
openssl s_server -accept "$PORT" -cert "$CERT" -key "$KEY" -www -quiet >"$SLOG" 2>&1 &
SRV_PID=$!

# wait for the port to accept (max ~5s)
i=0
while [ $i -lt 50 ]; do
  if openssl s_client -connect "127.0.0.1:$PORT" </dev/null >/dev/null 2>&1; then break; fi
  i=$((i + 1)); sleep 0.1
done

# ---- run the client ----
OUT=$(timeout 30 "$CLIENT" "https://127.0.0.1:$PORT/" 2>&1)
RC=$?
say "$OUT"

if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q '^ALL OK$'; then
  say "tls-openssl-devtest OK (real HTTPS handshake + GET via OpenSSL backend)"
  exit 0
else
  say "FAIL: client rc=$RC (expected ALL OK)"
  exit 1
fi

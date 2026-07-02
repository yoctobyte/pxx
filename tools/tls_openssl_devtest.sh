#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
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
PORT2=28772
CERT=/tmp/pxx_tls_devtest_cert.pem
KEY=/tmp/pxx_tls_devtest_key.pem
SLOG=/tmp/pxx_tls_devtest_sserver.log
CLIENT=/tmp/pxx_devtest_tls_openssl
INTEROP=/tmp/pxx_devtest_tls_interop
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

# ---- self-signed cert (CN + SAN = localhost) + loopback TLS server ----
if ! openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" \
      -days 1 -nodes -subj "/CN=localhost" \
      -addext "subjectAltName=DNS:localhost" >/dev/null 2>&1; then
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

# ---- test 1: our client vs openssl s_server (verify reject/accept + async) ----
say "--- client vs openssl s_server ---"
OUT=$(timeout 30 "$CLIENT" "$PORT" "$CERT" 2>&1)
RC=$?
say "$OUT"
if [ $RC -ne 0 ] || ! printf '%s' "$OUT" | grep -q '^ALL OK$'; then
  say "FAIL: client rc=$RC (expected ALL OK)"; exit 1
fi

# server no longer needed
kill "$SRV_PID" 2>/dev/null; SRV_PID=""

# ---- test 2: our TLS server (SSL_accept) <-> our verified client, one reactor ----
say "--- interop: our server <-> our client ---"
if ! "$PXX_STABLE" -dPXX_DYNLIB_LIBC -Fu"$ROOT/lib/rtl/platform/posix" \
      "$ROOT/test/devtest_tls_interop.pas" "$INTEROP" >/tmp/pxx_tls_interop_build.log 2>&1; then
  say "FAIL: interop build"; tail -3 /tmp/pxx_tls_interop_build.log; exit 1
fi
OUT2=$(timeout 30 "$INTEROP" "$PORT2" "$CERT" "$KEY" 2>&1)
RC2=$?
say "$OUT2"
if [ $RC2 -ne 0 ] || ! printf '%s' "$OUT2" | grep -q '^ALL OK$'; then
  say "FAIL: interop rc=$RC2 (expected ALL OK)"; exit 1
fi

say "tls-openssl-devtest OK (client<->s_server verify + our server<->client interop)"
exit 0

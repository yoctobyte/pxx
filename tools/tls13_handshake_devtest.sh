#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
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

kill "$SRV_PID" 2>/dev/null; SRV_PID=""

# ---- the OTHER signature schemes -------------------------------------------
# Runs 1 and 2 use ed25519, which for a long time was the ONLY scheme the
# client could verify -- every other one printed "verifier not wired here" and
# CARRIED ON, i.e. the handshake was accepted without the server ever proving
# possession of its key. The test was green precisely because it used the one
# algorithm that worked. These runs cover the two that did not:
#   RSA   -> rsa_pss_rsae_sha256 (0804), what most real RSA servers choose
#   ECDSA -> ecdsa_secp256r1_sha256 (0403)
scheme_run() {
  scheme_name=$1; ca_args=$2; leaf_args=$3; expect=$4
  SKEY=/tmp/pxx_tls13_s_$scheme_name.key;  SCA=/tmp/pxx_tls13_s_$scheme_name.ca.pem
  SLK=/tmp/pxx_tls13_s_$scheme_name.leaf.key; SCSR=/tmp/pxx_tls13_s_$scheme_name.csr
  SLP=/tmp/pxx_tls13_s_$scheme_name.leaf.pem; SDER=/tmp/pxx_tls13_s_$scheme_name.ca.der
  # shellcheck disable=SC2086
  openssl req -x509 $ca_args -keyout "$SKEY" -out "$SCA" -days 1 -nodes \
    -subj "/CN=PXX Test Root CA $scheme_name" >/dev/null 2>&1 || { say "SKIP  $scheme_name: CA gen failed"; return 0; }
  # shellcheck disable=SC2086
  openssl req $leaf_args -keyout "$SLK" -out "$SCSR" -nodes \
    -subj "/CN=localhost" >/dev/null 2>&1 || { say "SKIP  $scheme_name: leaf csr failed"; return 0; }
  openssl x509 -req -in "$SCSR" -CA "$SCA" -CAkey "$SKEY" -CAcreateserial -days 1 \
    -extfile "$EXT" -out "$SLP" >/dev/null 2>&1 || { say "SKIP  $scheme_name: leaf sign failed"; return 0; }
  openssl x509 -in "$SCA" -outform DER -out "$SDER" 2>/dev/null
  # Re-read the clock: $NOW was taken before the ed25519 runs, and these certs
  # are minted afterwards, so their notBefore is LATER than it -- the client
  # would correctly reject them as not-yet-valid and the failure would look
  # like a signature problem.
  SNOW=$(date -u +%Y%m%d%H%M%S)

  openssl s_server -accept "$PORT" -cert "$SLP" -key "$SLK" -tls1_3 -www -quiet >"$SLOG" 2>&1 &
  SRV_PID=$!
  i=0; while [ $i -lt 50 ]; do openssl s_client -connect "127.0.0.1:$PORT" -tls1_3 </dev/null >/dev/null 2>&1 && break; i=$((i+1)); sleep 0.1; done

  say "--- run: $scheme_name server ---"
  OUTS=$(timeout 30 "$CLIENT" "$PORT" "$SDER" "$SNOW" no-ktls 2>&1); RCS=$?
  say "$OUTS"
  kill "$SRV_PID" 2>/dev/null; SRV_PID=""
  rm -f "$SKEY" "$SCA" "$SLK" "$SCSR" "$SLP" "$SDER"
  if [ $RCS -eq 0 ] && printf '%s' "$OUTS" | grep -q '^ALL OK' \
     && printf '%s' "$OUTS" | grep -q "certverify=ok ($expect)"; then
    say "OK    $scheme_name (certverify=$expect)"
    return 0
  fi
  say "FAIL  $scheme_name (expected certverify=ok ($expect))"
  return 1
}

PASS3=1; scheme_run rsa   "-newkey rsa:2048" "-newkey rsa:2048" "rsa_pss_sha256" || PASS3=0
PASS4=1; scheme_run ecdsa "-newkey ec -pkeyopt ec_paramgen_curve:P-256" \
                          "-newkey ec -pkeyopt ec_paramgen_curve:P-256" "ecdsa_p256" || PASS4=0

if [ $PASS1 -eq 1 ] && [ $PASS2 -eq 1 ] && [ $PASS3 -eq 1 ] && [ $PASS4 -eq 1 ]; then
  say "tls13-handshake-devtest OK (ed25519 + rsa_pss + ecdsa_p256; chain verify; kTLS-TX + Pascal fallback)"
  exit 0
else
  say "FAIL: ed25519 run1=$PASS1 run2=$PASS2 rsa=$PASS3 ecdsa=$PASS4"
  exit 1
fi

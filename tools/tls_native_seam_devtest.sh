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
# MINT_ERR carries openssl's own reason out to the caller. Without it, "this
# openssl has no ed25519", "the disk is full" and "the umask is wrong" were one
# observation, and the caller spelled all three `SKIP` with exit 0 -- the same
# word and code it uses for openssl being ABSENT. Present-and-failing is not
# absent; see gen_or_bail in tools/tls13_handshake_devtest.sh.
MINT_ERR=""
mint() {
  nm=$1; keyargs=$2
  # shellcheck disable=SC2086
  MINT_ERR="$(openssl req -x509 $keyargs -keyout "$D.$nm.cakey" -out "$D.$nm.ca" \
    -days 1 -nodes -subj "/CN=PXX Seam CA $nm" 2>&1 >/dev/null)" || return 1
  # shellcheck disable=SC2086
  MINT_ERR="$(openssl req $keyargs -keyout "$D.$nm.key" -out "$D.$nm.csr" -nodes \
    -subj "/CN=localhost" 2>&1 >/dev/null)" || return 1
  MINT_ERR="$(openssl x509 -req -in "$D.$nm.csr" -CA "$D.$nm.ca" -CAkey "$D.$nm.cakey" \
    -CAcreateserial -days 1 -extfile "$D.ext" -out "$D.$nm.leaf" 2>&1 >/dev/null)" || return 1
  MINT_ERR=""
  return 0
}
mint_or_bail() {   # $1 = scheme name, $2 = openssl key args
  mint "$1" "$2" && return 0
  say "INCONCLUSIVE: $1 keygen failed -- openssl is present but could not do it"
  say "  openssl said: ${MINT_ERR:-(nothing on stderr)}"
  say "  This is NOT a pass. The $1 seam was not exercised."
  exit 2
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

mint_or_bail rsa "-newkey rsa:2048"
mint_or_bail ed  "-newkey ed25519"
mint_or_bail ec  "-newkey ec -pkeyopt ec_paramgen_curve:P-256"

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

# The SAME request over the ASYNC reactor path. Not redundant with the row
# above: the async path makes the fd NON-BLOCKING before the handshake runs, so
# it is the only row that covers EAGAIN handling -- the row above passed for
# months while every async https request failed with a bogus "connection
# closed". Plain Spawn on purpose: it also asserts the DEFAULT coroutine stack
# is big enough for a handshake.
ACLI=/tmp/pxx_devtest_https_native_async
if "$PXX_STABLE" -Fu"$ROOT/lib/rtl" -Fu"$ROOT/lib/rtl/platform/posix" \
      "$ROOT/test/devtest_https_native_async.pas" "$ACLI" >/tmp/pxx_https_async_build.log 2>&1; then
  serve 28829 "$D.rsa.leaf" "$D.rsa.key"
  out=$(SSL_CERT_FILE="$D.rsa.ca" timeout 40 "$ACLI" "https://localhost:28829/" 2>&1)
  kill "$SRV_PID" 2>/dev/null; SRV_PID=""
  if printf '%s' "$out" | grep -q '^ASYNC HTTPS OK'; then
    say "OK    HttpRequestAsync over https (non-blocking fd, default stack)"
  else
    say "FAIL  HttpRequestAsync over https"; printf '%s\n' "$out" | sed 's/^/      /'; fail=1
  fi
else
  say "FAIL  async https client build"; tail -3 /tmp/pxx_https_async_build.log; fail=1
fi

# A LARGE body, both paths. The two rows above fetch openssl's status page --
# a handshake plus a couple of application-data records, which can complete
# without a single would-block. So they cannot fail the way the HANDSHAKE
# failed for months: a short read taken as end-of-stream. In the data path that
# same shape truncates a body instead of refusing a connection, and a truncated
# body still parses, still says 200, and still looks like a success.
#
# THE EXPECTATION IS DERIVED FROM THE SERVED FILE, not written down. `wc -c` and
# an od/awk byte sum are computed from big.bin on every run, so nobody has to
# keep a constant in step with a fixture, and the body is built by repeating a
# file already in the tree -- deterministic, varied bytes, no generator
# dependency beyond what a POSIX shell has.
#
# LENGTH AND SUM BOTH, because neither subsumes the other: truncation moves the
# length, and a dropped or reordered record in the middle keeps the length and
# moves the sum.
#
# SYNC IS THE POSITIVE CONTROL FOR ASYNC. Same URL, same binary, one argv word
# apart -- so async red with sync green implicates the reactor and exonerates
# the server, the certificate and the body. That is the control that made the
# 2026-09-01 handshake defect legible.
#
# AND THE LAST ROW IS THE CONTROL ON THE CONTROL: the same client fetches a
# SMALL file and the harness asserts the comparison REJECTS it. A length-and-sum
# check that is silently comparing nothing passes every positive row.
SCLI=/tmp/pxx_devtest_https_native_stream
if "$PXX_STABLE" -Fu"$ROOT/lib/rtl" -Fu"$ROOT/lib/rtl/platform/posix" \
      "$ROOT/test/devtest_https_native_stream.pas" "$SCLI" >/tmp/pxx_https_stream_build.log 2>&1; then
  SD=/tmp/pxx_seam_www
  mkdir -p "$SD"
  : > "$SD/big.bin"
  while [ "$(wc -c < "$SD/big.bin")" -lt 2000000 ]; do
    cat "$ROOT/compiler/pasparser_expr.inc" >> "$SD/big.bin"
  done
  printf 'small\n' > "$SD/small.bin"
  explen=$(wc -c < "$SD/big.bin" | tr -d ' ')
  expsum=$(od -An -v -tu1 "$SD/big.bin" | awk '{for(i=1;i<=NF;i++) s+=$i} END{print s+0}')

  # s_server -WWW, not -HTTP: -HTTP answered nothing at all here, verified with
  # curl (code=000) while -WWW served the full 2 MB (code=200 size=2000000).
  ( cd "$SD" && exec openssl s_server -accept 28830 -cert "$D.rsa.leaf" \
      -key "$D.rsa.key" -tls1_3 -WWW ) >/dev/null 2>&1 &
  SRV_PID=$!
  i=0; while [ $i -lt 50 ]; do
    openssl s_client -connect "127.0.0.1:28830" -tls1_3 </dev/null >/dev/null 2>&1 && break
    i=$((i+1)); sleep 0.1
  done

  check_stream() {
    mode=$1; url=$2; want=$3
    o=$(SSL_CERT_FILE="$D.rsa.ca" timeout 90 "$SCLI" "$url" "$mode" 2>&1)
    gl=$(printf '%s\n' "$o" | sed -n 's/^len=//p')
    gs=$(printf '%s\n' "$o" | sed -n 's/^sum=//p')
    if [ "$gl" = "$explen" ] && [ "$gs" = "$expsum" ]; then r=match; else r=mismatch; fi
    if [ "$r" = "$want" ]; then
      say "OK    2 MB body over https ($mode, expected $want)"
    else
      say "FAIL  2 MB body over https ($mode): wanted $want, got $r"
      say "      expected len=$explen sum=$expsum"
      printf '%s\n' "$o" | sed 's/^/      /'
      fail=1
    fi
  }
  check_stream sync  "https://localhost:28830/big.bin"   match
  check_stream async "https://localhost:28830/big.bin"   match
  check_stream async "https://localhost:28830/small.bin" mismatch
  kill "$SRV_PID" 2>/dev/null; SRV_PID=""
else
  say "FAIL  stream client build"; tail -3 /tmp/pxx_https_stream_build.log; fail=1
fi

if [ "$fail" -eq 0 ]; then
  say "tls-native-seam-devtest OK (3 schemes, 4 refusals, https via http.pas, sync + async, 2 MB body both paths)"
  exit 0
fi
say "tls-native-seam-devtest FAILED"
exit 1

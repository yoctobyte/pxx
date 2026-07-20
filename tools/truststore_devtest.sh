#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# Hermetic chain-validation devtest for lib/rtl/truststore.pas
# (feature-tls-system-trust-store).
#
# Generates a root -> intermediate -> leaf chain with the openssl CLI, then
# asserts that truststore accepts the good chain and rejects the bad ones.
# No network: the only anchor is the test root we just made.
#
# NOT in the hermetic lib-test gate (needs the openssl CLI). Skips cleanly
# (exit 0) when openssl is absent; exits non-zero only on a genuine failure.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PXX_STABLE=${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}
DIR=/tmp/pxx_truststore_devtest
BIN=/tmp/pxx_devtest_truststore

say() { printf '%s\n' "$*"; }

cleanup() { rm -rf "$DIR"; }
trap cleanup EXIT INT TERM

if ! command -v openssl >/dev/null 2>&1; then
  say "truststore-devtest: openssl CLI not found — skipping (not a failure)."
  exit 0
fi
if [ ! -x "$PXX_STABLE" ]; then
  say "truststore-devtest: no stable compiler at $PXX_STABLE — skipping."
  exit 0
fi

rm -rf "$DIR"; mkdir -p "$DIR"

say "truststore-devtest: generating root -> intermediate -> leaf"
openssl req -x509 -newkey rsa:2048 -keyout "$DIR/root.key" -out "$DIR/root.pem" \
  -days 3650 -nodes -subj "/CN=PXX Test Root" >/dev/null 2>&1 || {
    say "FAIL: could not generate the root"; exit 1; }

openssl req -newkey rsa:2048 -keyout "$DIR/int.key" -out "$DIR/int.csr" \
  -nodes -subj "/CN=PXX Test Intermediate" >/dev/null 2>&1
printf 'basicConstraints=CA:TRUE\n' > "$DIR/int.ext"
openssl x509 -req -in "$DIR/int.csr" -CA "$DIR/root.pem" -CAkey "$DIR/root.key" \
  -CAcreateserial -out "$DIR/int.pem" -days 3650 -extfile "$DIR/int.ext" >/dev/null 2>&1 || {
    say "FAIL: could not sign the intermediate"; exit 1; }

openssl req -newkey rsa:2048 -keyout "$DIR/leaf.key" -out "$DIR/leaf.csr" \
  -nodes -subj "/CN=test.example.com" >/dev/null 2>&1
printf 'subjectAltName=DNS:test.example.com\n' > "$DIR/leaf.ext"
openssl x509 -req -in "$DIR/leaf.csr" -CA "$DIR/int.pem" -CAkey "$DIR/int.key" \
  -CAcreateserial -out "$DIR/leaf.pem" -days 3650 -extfile "$DIR/leaf.ext" >/dev/null 2>&1 || {
    say "FAIL: could not sign the leaf"; exit 1; }

for f in root int leaf; do
  openssl x509 -in "$DIR/$f.pem" -outform DER -out "$DIR/$f.der" || exit 1
done
# the "system store" for this run: the test root, and nothing else
cp "$DIR/root.pem" "$DIR/store.pem"

# `now` must sit inside the leaf's validity window. The certificates were just
# issued, so anything a day out is safely after notBefore and long before
# notAfter — deriving it beats hardcoding a date that rots.
NOW=$(date -u -d '+1 day' '+%Y%m%d%H%M%S' 2>/dev/null) \
  || NOW=$(date -u -v+1d '+%Y%m%d%H%M%S' 2>/dev/null) \
  || NOW=$(date -u '+%Y%m%d%H%M%S')

say "truststore-devtest: building"
"$PXX_STABLE" -Fu"$ROOT/lib/rtl" -Fu"$ROOT/lib/rtl/platform/posix" \
  "$ROOT/test/devtest_truststore.pas" "$BIN" >/dev/null || {
    say "FAIL: could not build devtest_truststore"; exit 1; }

say "truststore-devtest: running (now=$NOW)"
"$BIN" "$DIR" "$NOW"
rc=$?
if [ "$rc" -ne 0 ]; then
  say "truststore-devtest: FAILED"
  exit 1
fi
say "truststore-devtest: OK"
exit 0

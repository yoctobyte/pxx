#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Devtest for tools/release.sh's pin-identity check (pin_identity + the first
# guard in publish). Both outcomes, and never a real publish:
#   1. MATCH: the release compiler is byte-identical to the pinned binary.
#      pin_identity prints "release binary == pin vN" and returns 0, and
#      publish gets PAST the pin guard, then stops at the next guard (a dirty
#      tree, faked). That stop is the control that the guard lets a pin through.
#   2. MISMATCH: one byte differs. pin_identity prints "NOT A PIN" and returns
#      1, and publish refuses before any prompt.
#   3. no pinned binary at all: NOT A PIN, and publish refuses.
# git and gh are shell functions here that only record their arguments. Every
# case asserts that no `tag`, `push` or `release` was ever attempted, so a guard
# that failed open could not publish anything even from this test.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REL="$PWD/tools/release.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  PASS $1"; }
bad() { echo "  FAIL $1 -- $2"; fail=1; }

mkdir -p "$T/pin" "$T/nopin"
head -c 4096 /dev/urandom > "$T/pin/pinned"
echo 777 > "$T/pin/VERSION"
cp "$T/pin/pinned" "$T/same"
cp "$T/pin/pinned" "$T/diff"; printf 'X' | dd of="$T/diff" bs=1 seek=100 conv=notrunc 2>/dev/null

# run <compiler> <pindir> <shell snippet>: release.sh's functions, no main.
run() {
  ( source <(sed '$d' "$REL")
    COMPILER="$1"; PIN_DIR="$2"
    git() { echo "git $*" >> "$T/calls"; [ "$1" = status ] && echo " M fake-dirty"; return 0; }
    gh()  { echo "gh $*"  >> "$T/calls"; return 0; }
    eval "$3" ) < /dev/null 2>&1
}
no_publish() { ! grep -qE '^(git (tag|push)|gh release|gh workflow)' "$T/calls" 2>/dev/null; }

: > "$T/calls"
out=$(run "$T/same" "$T/pin" 'pin_identity'); rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^release binary == pin v777 ' \
  && ok "identical binary: pin_identity says == pin v777, rc 0" || bad "match" "rc=$rc $out"

out=$(run "$T/same" "$T/pin" 'publish v9.9.9 Test'); rc=$?
[ "$rc" != 0 ] && echo "$out" | grep -q 'working tree dirty' && ! echo "$out" | grep -q 'not the pinned' && no_publish \
  && ok "identical binary: publish passes the pin guard, stops at the next guard, nothing tagged" \
  || bad "match publish" "rc=$rc $out"

: > "$T/calls"
out=$(run "$T/diff" "$T/pin" 'pin_identity'); rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^NOT A PIN (release ' \
  && ok "one byte different: NOT A PIN, rc 1" || bad "mismatch" "rc=$rc $out"

out=$(run "$T/diff" "$T/pin" 'publish v9.9.9 Test'); rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q 'publish: the release binary is not the pinned binary' && no_publish \
  && ! grep -q '^git status' "$T/calls" \
  && ok "one byte different: publish refuses FIRST, before any other guard, nothing tagged" \
  || bad "mismatch publish" "rc=$rc $out"

: > "$T/calls"
out=$(run "$T/same" "$T/nopin" 'publish v9.9.9 Test'); rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q 'NOT A PIN (no pinned binary' && no_publish \
  && ok "no pin present: NOT A PIN, publish refuses" || bad "no pin" "rc=$rc $out"

[ "$fail" = 0 ] && echo "release_pin_identity_devtest: all green" || { echo "release_pin_identity_devtest: RED"; exit 1; }

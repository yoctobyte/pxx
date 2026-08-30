#!/bin/sh
# The two WASI capability models, asked the same questions and compared against
# EACH OTHER.
#
# There are two implementations of preopen resolution and rights in this tree —
# compiler/builtin/wasibackend.pas (reached through the sysopen/sysread/sysclose
# INTRINSICS, the path the wasm-hosted compiler takes) and
# lib/rtl/platform/wasi/platform_backend.pas (reached through PalOpen/PalRead,
# the path every ordinary program takes). The duplication is deliberate and
# pending decide-which-way-the-wasi-capability-model-should-point-once-it-has-
# one-owner; this check is what makes it SAFE to leave in place meanwhile.
#
# WHAT IT CATCHES, AND THE LIMIT — the limit is structural and stating it is the
# point, because a green tick here is easy to over-trust.
#
#   CATCHES: divergence. One model opening a path the other refuses, or reading
#   different bytes from the same file. That is what two copies drift into, and
#   no other check can see it because each path is exercised alone.
#
#   CANNOT CATCH: a defect IDENTICAL IN BOTH. The copies are each other's only
#   oracle, so a bug copied at birth makes them agree and this goes green.
#   Not hypothetical: the u64 alignment defect
#   (bug-wasm-hosted-compiler-segfaults-the-host-after-a-successful-parse) was
#   exactly that — in both, agreed by both, caught only by a strict HOST
#   refusing the module. check_align.sh covers that class. These two checks are
#   complements and neither subsumes the other.
#
# THE REFUSALS ARE THE ASSERTION, not the accepts. A capability model's job is
# saying no — `..` climbing out of the preopen, an absolute path the host never
# granted, an empty path. Two models agreeing on what they OPEN while disagreeing
# on what they REFUSE differ in precisely the direction that matters, and a test
# that only opened files would call them identical.
#
# NATIVE IS NOT THE ORACLE HERE, and that is deliberate. On posix
# `../wd_outside.txt` is an ordinary readable file; under WASI it must be
# refused because no preopen covers it. So the two wasm models are each other's
# oracle. What guards against the vacuous pass — both models refusing
# EVERYTHING, which agrees trivially — is the positive control below: both
# outcomes must actually occur.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-wasidiff.$$
mkdir -p "$work/sand/wd_sub"
trap 'rm -rf "$work"' EXIT

cp "$here/wasihost.js" "$work/"
printf 'diff-payload'   > "$work/sand/wd_data.txt"
printf 'nested-payload' > "$work/sand/wd_sub/wd_nested.txt"
# OUTSIDE the preopen. If either model ever reaches this, the escape cases below
# turn from REFUSE into ACCEPT and the run fails — the file's whole purpose.
printf 'SHOULD-NOT-BE-REACHABLE' > "$work/wd_outside.txt"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`.
"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/wasidiff_slice.pas" "$work/wd.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/wd.wasm"

# Both models live in ONE module here, which is not incidental: it is the
# measured reason a shared {$i} include cannot unify them (it would define every
# symbol twice), so this is also the standing proof that the co-occurrence the
# decision rests on is real.
for sym in PXXWasiOpen PalBackendOpen; do
  if ! wasm-objdump -x "$work/wd.wasm" 2>/dev/null | grep -q "<$sym>"; then
    echo "FAIL $sym is not in the module, so this slice is not comparing two"
    echo "     implementations at all and its agreement is meaningless"
    exit 1
  fi
done
echo "ok  both capability models are present in ONE module — the comparison is"
echo "..  real, and the co-occurrence a shared include would have to survive is"
echo "..  demonstrated rather than assumed"

node --no-warnings "$work/wasihost.js" "$work/wd.wasm" "$work/sand" > "$work/nd.txt" 2>&1
run_wasmtime=0
if command -v wasmtime >/dev/null 2>&1; then
  wasmtime run --dir "$work/sand"::. "$work/wd.wasm" > "$work/wt.txt" 2>&1
  run_wasmtime=1
fi

check_output() {
  f=$1; host=$2
  [ -s "$f" ] || { echo "FAIL $host produced no output"; exit 1; }
  if grep -q 'agree=FALSE' "$f" || grep -q 'bytes=DIFFER' "$f"; then
    echo "FAIL the two WASI capability models DIVERGED under $host:"
    grep -E 'agree=FALSE|bytes=DIFFER' "$f"
    echo "     One of wasibackend.pas / platform_backend.pas answers a path"
    echo "     differently from the other. They are copies; a fix landed in one"
    echo "     and not the other is the expected cause."
    exit 1
  fi
  grep -qx 'disagreements=0' "$f" || {
    echo "FAIL $host: disagreements counter is not 0"; grep '^disagreements=' "$f"; exit 1; }

  # The POSITIVE CONTROL. "Everything refused" agrees trivially, and a sandbox
  # that failed to stage would produce exactly that while looking green.
  a=$(sed -n 's/^accepts=//p' "$f"); r=$(sed -n 's/^refuses=//p' "$f")
  [ "${a:-0}" -ge 3 ] || { echo "FAIL $host: only ${a:-0} accepts — the sandbox did not stage, so"; echo "     agreement here is vacuous"; exit 1; }
  [ "${r:-0}" -ge 4 ] || { echo "FAIL $host: only ${r:-0} refuses — the capability cases are not being"; echo "     exercised, which is the half this check exists for"; exit 1; }

  # Named individually: an escape that starts being ACCEPTED is a capability
  # breach, not merely a divergence, and it must not be reported as a counter.
  for esc in escape deepesc abs-etc; do
    grep -E "^$esc +intrinsic=REFUSE pal=REFUSE" "$f" >/dev/null || {
      echo "FAIL $host: '$esc' was ACCEPTED by at least one model. A path"
      echo "     outside every preopen must be refused — this is the capability"
      echo "     boundary, not a preference."
      grep "^$esc" "$f"; exit 1; }
  done
}

check_output "$work/nd.txt" node
echo "ok  node: the two models agree on all 9 paths, and the three escape cases"
echo "..  (.. out of the preopen, .. through a subdir, an absolute path) are"
echo "..  REFUSED by both — asserted by name, not by a counter"

if [ "$run_wasmtime" = 1 ]; then
  check_output "$work/wt.txt" wasmtime
  # The two HOSTS must also agree, now that the slice prints nothing
  # host-dependent. This is what caught the directory-read errno (-9 vs -1)
  # being printed in an earlier version.
  if diff -u "$work/nd.txt" "$work/wt.txt" > "$work/hostdiff.txt"; then
    echo "ok  wasmtime agrees too, and the two HOSTS produce identical output"
  else
    echo "FAIL node and wasmtime disagree about the same module:"
    cat "$work/hostdiff.txt"; exit 1
  fi
else
  echo "ok  node only — wasmtime is not on PATH, so the strict-host half of"
  echo "..  this check did not run (check_align.sh reports the same absence)"
fi

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/wasidiff_slice.pas" "$work" wd \
   -Fulib/rtl/platform/wasi

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_wasidiff"

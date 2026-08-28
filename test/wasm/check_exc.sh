#!/bin/sh
# Phase 7: exceptions.
#
# wasm has no code addresses, so none of setjmp, longjmp or a raise stub is
# expressible and `exception_emit.inc` emits no runtime bytes for this target.
# Unwinding is instead two mechanisms sharing one question — is the innermost
# handler frame MINE? — answered at a raise and again after every call:
#
#   yes  ->  $pc := the pad's basic block, br $dispatch     (handled here)
#   no   ->  set $exc_pending, restore $sp, return          (propagate out)
#
# So the two halves fail independently, and a slice that stays inside one frame
# exercises neither the comparison nor the propagation. exc_slice.pas is built
# around that: nine compositions, every one of which crosses at least one of
# the seams — frames, loops, finally continuations, re-raise, class matching,
# and a raise from VALUE position, where the call's result is on the operand
# stack when the check branches.
#
# What would survive a revert, and how each assertion is arranged not to:
#
#   * delete the lowering and the bodies go `unreachable`; the module traps and
#     both the coverage assertion and the diff fail;
#   * get the pad wrong and the WRONG HANDLER runs — which prints, so the diff
#     fails on a line rather than on a crash. That is why nearly every branch
#     of the slice writes something, including the ones that must NOT run: a
#     line named `-unreachable` appearing in the output IS the failure;
#   * lose the propagation and an unhandled exception exits 0, which is the
#     `Halt(7) exits 0` shape — asserted below on the exit code AND the
#     stderr line, natively and through the host;
#   * lose the ExceptionUsed gate and every module in the project grows a
#     check after every call. Nothing in a differential can see that, because
#     the checks are correct — just universal. Asserted in the negative, on a
#     module that uses no exceptions at all.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-exc.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/exc_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# The slice must still be exercising the paths it claims to. Every `-unreachable`
# branch is a trap laid for a wrong landing pad, and they are only traps while
# the ORACLE agrees they do not run.
if grep -q 'unreachable' "$work/native.txt"; then
  echo "FAIL the native build reached a branch marked unreachable — the slice"
  echo "..   is wrong, or the frontend is:"
  grep 'unreachable' "$work/native.txt"
  exit 1
fi
echo "ok  no -unreachable branch runs natively (they stay traps for a bad pad)"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`. Capture, then trim.
"$root/compiler/pascal26" --target=wasm32 \
    "$here/exc_slice.pas" "$work/e.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/e.wasm"

if grep -qE '^    (Deep|Middle|Val|EarlyExit|main\$0) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Deep|Middle|Val|EarlyExit|main\$0) ' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
const sp0 = inst.exports.sp.value;
let exited = null;
try { inst.exports.main(); }
catch (e) { if (e instanceof h.HostExit) exited = e.code; else throw e; }
// $sp back where it started. Recursion is not what makes this sharp here —
// unwinding is: every frame an exception passed through skipped its own
// epilogue, so the restore has to have happened on the unwind path too.
if (exited === null && inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(h.text(1));
process.stderr.write(h.text(2));
if (exited !== null) process.exitCode = exited;
JS

node "$work/run.js" "$work/e.wasm" > "$work/wasm.txt" 2>"$work/wasm.err"
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  nested try/finally, an exception across two frames, escape from a"
  echo "..  loop, catch-and-re-raise, break and Exit through a finally, a raise"
  echo "..  from value position, typed handlers with a descendant class, an"
  echo "..  unmatched arm falling outward, and a raise inside a handler."
  echo "..  \$sp balanced across every unwind."
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# ---- unhandled: it must not look like success -----------------------------
cat > "$work/unh.pas" <<'PAS'
program Unhandled;
begin
  writeln('before');
  raise 99;
  writeln('unreachable');
end.
PAS

"$root/compiler/pascal26" "$work/unh.pas" "$work/unh" >/dev/null
set +e
"$work/unh" > "$work/unh.out" 2> "$work/unh.err"
nrc=$?
set -e

"$root/compiler/pascal26" --target=wasm32 "$work/unh.pas" "$work/unh.wasm" \
    > /dev/null 2>&1
set +e
node "$work/run.js" "$work/unh.wasm" > "$work/unhw.out" 2> "$work/unhw.err"
wrc=$?
set -e

if [ "$nrc" != "217" ] || [ "$wrc" != "217" ]; then
  echo "FAIL unhandled exception exit code: native $nrc, wasm $wrc (want 217)"
  exit 1
fi
if ! diff -u "$work/unh.out" "$work/unhw.out"; then
  echo "FAIL stdout before the unhandled raise differs"; exit 1
fi
if ! grep -q 'Unhandled exception' "$work/unhw.err"; then
  echo "FAIL wasm said nothing on stderr about the unhandled exception:"
  cat "$work/unhw.err"
  exit 1
fi
echo "ok  an unhandled exception exits 217 and says so on fd 2, agreeing with"
echo "..  the native build on the exit code and on the output before it"

# ---- the gate, asserted in the negative -----------------------------------
# A program with no `raise` anywhere must carry NO trace of the mechanism: no
# pending flag, and therefore no check after any call. Nothing in a
# differential can see this — the checks would be correct, merely universal —
# so it is asserted directly, on a module that is exercised by another suite
# and so cannot quietly stop being representative.
"$root/compiler/pascal26" --target=wasm32 \
    "$here/frozen_slice.pas" "$work/noexc.wat" > /dev/null 2>&1
if grep -q 'exc_pending' "$work/noexc.wat"; then
  echo "FAIL a module with no exceptions declares the pending flag — the"
  echo "..   ExceptionUsed gate is gone and every call in the project now"
  echo "..   carries a check that can never fire"
  exit 1
fi
"$root/compiler/pascal26" --target=wasm32 \
    "$here/exc_slice.pas" "$work/e.wat" > /dev/null 2>&1
if ! grep -q 'exc_pending' "$work/e.wat"; then
  echo "FAIL the exception slice does NOT declare the pending flag, so the"
  echo "..   assertion above is passing for the wrong reason"
  exit 1
fi
echo "ok  the mechanism appears only in modules that use it (asserted both"
echo "..  ways, so the negative cannot pass by naming the wrong thing)"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/exc_slice.pas" "$work" e

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_exc"

#!/bin/sh
# Phase 6: the module reaches its HOST — stdout through fd_write, and exit
# through proc_exit.
#
# `external 'lib' name 'sym'` IS a wasm import — the module/field pair a wasm
# import needs is exactly what the Pascal form already carries, and what the
# parser already records (ProcLibrary / ProcExtName). So this is the first
# module the compiler emits with an import in it, and that makes it the first
# one that can catch a whole class of bug the other seven suites structurally
# cannot see: imports occupy the LOW function indices, so registering one
# shifts every DEFINED function's index by one. A module whose indices were
# baked before that still validates — every callee has some signature and
# enough of them match — and calls the wrong functions.
#
# Measured: with the relocation removed, a module with an import is rejected
# with 127 type errors, and a module WITHOUT one is accepted unchanged. The
# whole existing suite is in the second category. This file is the first thing
# in the project that exercises the first.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-host.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

# Every module imports proc_exit (the RTL error reporters all end in Halt),
# so a bare `{}` import object no longer instantiates. wasmhost.js is the one
# place that knows what a pxx module needs.
cp "$here/wasmhost.js" "$work/"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`. Capture, then trim.
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/host_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/w.wasm"

if grep -qE '^    (RawWrite|Emit|TryWriteln|fd_write) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (RawWrite|Emit|TryWriteln|fd_write) ' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

# The import must be declared with the module and field the SOURCE named, not
# with a backend-chosen default: the point of the mechanism is that the WASI
# surface is spelled in Pascal.
if wasm2wat "$work/w.wasm" | grep -q '(import "wasi_snapshot_preview1" "fd_write"'; then
  echo "ok  the import carries the module and field the source declared"
else
  echo "FAIL the module does not import wasi_snapshot_preview1.fd_write:"
  wasm2wat "$work/w.wasm" | grep '(import' || echo "     (no imports at all)"
  exit 1
fi

# ---- host 1: a hand-written fd_write --------------------------------------
# Decodes the iovec array itself, so it asserts the STRUCTURE the module built
# and not merely that some bytes arrived.
cat > "$work/run.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
const sp0 = inst.exports.sp.value;

const n = inst.exports.Emit();
if (h.writes.length !== 1 || h.writes[0].bytes.length !== 5) {
  console.error(`FAIL expected one 5-byte iovec, got ` +
                JSON.stringify(h.writes.map(w => w.bytes.length)));
  process.exit(1);
}
const text = h.text();
const fds  = [...new Set(h.writes.map(w => w.fd))];

// writeln(42) must produce NOTHING — PXXSysWrite has no wasm32 arm. Asserted
// as loudly as the output above, because the day it starts working is the day
// this file's claim about it stops being true.
h.reset();
inst.exports.TryWriteln();
const afterWriteln = h.writes.length;

if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(JSON.stringify(
  { n, text, fds, afterWriteln }) + '\n');
JS

res=$(node "$work/run.js" "$work/w.wasm")
expect='{"n":5,"text":"wasm\n","fds":[1],"afterWriteln":0}'
if [ "$res" = "$expect" ]; then
  echo "ok  the module wrote 5 bytes of 'wasm' to fd 1 through its own import"
else
  echo "FAIL host saw: $res"
  echo "     expected: $expect"
  exit 1
fi

# ---- host 2: node's real WASI ---------------------------------------------
# An independent implementation of the same interface. A hand-written shim can
# be lenient about an iovec our module got subtly wrong; a real one is not.
# Two uncorrelated readers of the same bytes is what makes this a check rather
# than a restatement of what the module already believes.
cat > "$work/wasi.js" <<'JS'
const fs = require('fs');
const { WASI } = require('node:wasi');
const wasi = new WASI({ version: 'preview1', args: [], env: {},
                        returnOnExit: true });
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])),
  wasi.getImportObject());
// Not a WASI command (there is no _start), so it is initialised as a reactor
// and its exports called directly.
wasi.initialize(inst);
process.stdout.write(String(inst.exports.Emit()) + '\n');
JS
if node "$work/wasi.js" "$work/w.wasm" 2>/dev/null > "$work/wasi.txt"; then
  if [ "$(cat "$work/wasi.txt")" = "wasm
5" ]; then
    echo "ok  node's real WASI agrees: same 5 bytes, same fd"
  else
    echo "FAIL node:wasi disagrees with the hand-written host:"
    cat "$work/wasi.txt"
    exit 1
  fi
else
  echo "FAIL node:wasi could not instantiate or run the module"
  node "$work/wasi.js" "$work/w.wasm" 2>&1 | tail -5
  exit 1
fi

# ---- writeln, and the one thing between it and working ---------------------
# `writeln` LOWERS on this target: IR_WRITE dispatches to the RTL's
# target-neutral console family (PXXWriteDecW / PXXWriteNL / PXXWriteCharW /
# PXXWriteBoolW / PXXWriteStrMW / PXXWriteFrozenW / PXXWriteCStr), written for
# hosted riscv32 with the comment "any backend could adopt them". This one
# adopts them unchanged.
#
# They all bottom out in PXXSysWrite, an ifdef chain over __pxxrawsyscall with
# an arm per target and no wasm32 arm — so it returns 0 having written nothing.
# builtinheap.pas is a SHARED file: bug-a-pxxsyswrite-has-no-wasm32-arm.
#
# `afterWriteln === 0` alone would be a WORTHLESS assertion, and it is worth
# saying why, because it is the exact shape a sibling lane hit today: a check
# can only gate behaviour its environment does not already supply. Silence is
# supplied here by default. Delete the IR_WRITE arm entirely and the write is
# skipped, TryWriteln returns normally, and `afterWriteln === 0` still passes —
# the assertion would be testing that nothing happened, which is what happens
# when nothing works.
#
# So the silence is asserted TOGETHER with the mechanism that is supposed to
# produce it. TryWriteln must actually contain the call chain: format the
# integer, then the newline. The pair distinguishes "lowered correctly and
# PXXSysWrite is inert" from "silently dropped", which the silence alone cannot.
# The .wat is the only readable view of what was emitted, and wat_oracle.sh
# below proves it describes the same module as the binary — so reading the
# text here is reading the binary, not a second thing that might disagree.
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/host_slice.pas" "$work/w.wat" >/dev/null 2>&1
body=$(awk '/\(func \$TryWriteln/,/^  \)/' "$work/w.wat")
if echo "$body" | grep -q 'call \$PXXWriteDecW' &&
   echo "$body" | grep -q 'call \$PXXWriteNL'; then
  echo "ok  writeln LOWERED: TryWriteln calls PXXWriteDecW then PXXWriteNL"
else
  echo "FAIL TryWriteln does not contain the write call chain — the silence"
  echo "     above is the write being DROPPED, not the write reaching an inert"
  echo "     PXXSysWrite. Body was:"
  echo "$body"
  exit 1
fi
echo "ok  KNOWN LIMITATION unchanged: writeln lowers and prints nothing —"
echo "..  PXXSysWrite has no wasm32 arm. bug-a-pxxsyswrite-has-no-wasm32-arm"
echo "..  The import path above is what that arm will be built on."

# ---- Halt(n) must EXIT WITH n --------------------------------------------
# `Halt` is a process-level operation with no wasm instruction behind it, so it
# lowers to WASI's proc_exit — declared by the BACKEND rather than named by an
# `external` declaration, because an IR op has no Pascal call site to hang one
# on. The failure this guards is the one hosted riscv32 shipped
# (bug-a-halt-n-exits-zero-on-hosted-riscv32): the argument evaluated nowhere,
# so `Halt(7)` returns 0 and a program's failure signal vanishes silently.
#
# Diffed against the native build, and read TWO ways: once as the host
# process's own exit status under node's real WASI (which is what a caller
# actually sees), and once through a hand-written proc_exit that records its
# argument (which is what the module actually passed). A wrong value that
# happened to survive one reading does not survive both.
cat > "$work/halt.pas" <<'PAS'
program HaltTest;
begin
  Halt(7);
end.
PAS
"$root/compiler/pascal26" "$work/halt.pas" "$work/halt_native" >/dev/null
set +e; "$work/halt_native"; native_code=$?; set -e

"$root/compiler/pascal26" --target=wasm32 "$work/halt.pas" "$work/halt.wasm" \
    >/dev/null 2>&1
cat > "$work/halt1.js" <<'JS'
const fs = require('fs');
const { WASI } = require('node:wasi');
const wasi = new WASI({ version: 'preview1', args: [], env: {},
                        returnOnExit: false });
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])),
  wasi.getImportObject());
wasi.initialize(inst);
inst.exports.main();
process.exit(99);   // reached only if Halt did NOT exit
JS
set +e; node "$work/halt1.js" "$work/halt.wasm" 2>/dev/null; wasi_code=$?; set -e

cat > "$work/halt2.js" <<'JS'
const fs = require('fs');
let code = null;
const imports = { wasi_snapshot_preview1: {
  proc_exit(c) { code = c; throw new Error('exit'); },
  fd_write() { return 0; },
}};
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), imports);
try { inst.exports.main(); } catch (e) { /* the unwind */ }
process.stdout.write(String(code) + '\n');
JS
arg_code=$(node "$work/halt2.js" "$work/halt.wasm")

if [ "$native_code" = 7 ] && [ "$wasi_code" = 7 ] && [ "$arg_code" = 7 ]; then
  echo "ok  Halt(7) exits 7 — native, WASI process status, and the argument"
  echo "..  proc_exit actually received, all three agreeing"
else
  echo "FAIL Halt(7): native=$native_code wasi=$wasi_code arg=$arg_code"
  [ "$wasi_code" = 99 ] && echo "     99 means Halt returned instead of exiting."
  exit 1
fi

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/host_slice.pas" "$work" w

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_host"

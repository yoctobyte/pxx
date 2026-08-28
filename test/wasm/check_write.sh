#!/bin/sh
# Phase 6, first milestone: the module reaches its HOST.
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
work=${TMPDIR:-/tmp}/pxx-wasm-write.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`. Capture, then trim.
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/write_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
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
let mem, out = [];
const imports = { wasi_snapshot_preview1: {
  fd_write(fd, iovs, iovsLen, nwritten) {
    const m = new DataView(mem.buffer);
    if (iovsLen !== 1) { console.error(`FAIL iovsLen=${iovsLen}, expected 1`); process.exit(1); }
    let total = 0;
    for (let i = 0; i < iovsLen; i++) {
      const p = m.getUint32(iovs + i * 8, true);
      const n = m.getUint32(iovs + i * 8 + 4, true);
      out.push({ fd, bytes: Array.from(new Uint8Array(mem.buffer, p, n)) });
      total += n;
    }
    m.setUint32(nwritten, total, true);
    return 0;
  },
}};
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), imports);
mem = inst.exports.memory;
const sp0 = inst.exports.sp.value;

const n = inst.exports.Emit();
const text = out.map(w => Buffer.from(w.bytes).toString('latin1')).join('');
const fds  = [...new Set(out.map(w => w.fd))];

// writeln(42) must produce NOTHING — PXXSysWrite has no wasm32 arm. Asserted
// as loudly as the output above, because the day it starts working is the day
// this file's claim about it stops being true.
out = [];
inst.exports.TryWriteln();
const afterWriteln = out.length;

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
# The assertion above (afterWriteln === 0) is the guard. Green here means "the
# known limitation is still exactly this one".
echo "ok  KNOWN LIMITATION unchanged: writeln lowers and prints nothing —"
echo "..  PXXSysWrite has no wasm32 arm. bug-a-pxxsyswrite-has-no-wasm32-arm"
echo "..  The import path above is what that arm will be built on."

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/write_slice.pas" "$work" w

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_write"

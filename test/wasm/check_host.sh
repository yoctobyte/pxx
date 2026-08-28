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

// Path 1: the raw import. One 5-byte iovec, decoded by the host rather than
// merely counted — a wrong pointer or length is a wrong STRUCTURE, and only
// something that reads the structure can tell.
const n = inst.exports.Emit();
if (h.writes.length !== 1 || h.writes[0].bytes.length !== 5) {
  console.error('FAIL expected one 5-byte iovec, got ' +
                JSON.stringify(h.writes.map(w => w.bytes.length)));
  process.exit(1);
}
const text = h.text();
const fds  = [...new Set(h.writes.map(w => w.fd))];
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(JSON.stringify({ n, text, fds }) + '\n');
JS

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
// This arm tests path 1 (the raw fd_write import) on its own, with path 2
// (writeln) not writing to the same fd. The caller compiles a second module
// with -dWASM_NOMAIN, which empties host_slice's program body, so starting it
// prints nothing and stdout below carries only Emit's bytes.
//
// `wasi.start`, not `wasi.initialize`. Every wasm32 program we emit exports
// `_start`, so node classifies all of them as commands and `initialize`
// refuses them by design. The isolation comes from main having nothing to do,
// not from the module being a reactor — an earlier version of this comment
// claimed -dWASM_NOMAIN made it one, and the slice did not even read the
// define.
wasi.start(inst);
process.stdout.write(String(inst.exports.Emit()) + '\n');
JS
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/host_slice.pas" "$work/reactor.wasm" > /dev/null 2>&1
if node "$work/wasi.js" "$work/reactor.wasm" 2>/dev/null > "$work/wasi.txt"; then
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
  node "$work/wasi.js" "$work/reactor.wasm" 2>&1 | tail -5
  exit 1
fi

# ---- writeln, diffed against the native build ------------------------------
# `writeln` takes the long way: IR_WRITE dispatches to the RTL's target-neutral
# console family (PXXWriteDecW / PXXWriteNL / PXXWriteCharW / PXXWriteBoolW /
# PXXWriteStrMW / PXXWriteFrozenW / PXXWriteCStr), written for hosted riscv32
# with the comment "any backend could adopt them"; this one adopts them
# unchanged. They bottom out in PXXSysWrite, whose wasm32 arm is itself an
# `external` declaration of the same kind path 1 uses directly.
#
# This block used to assert the OPPOSITE — that writeln printed nothing —
# because PXXSysWrite had no wasm32 arm, and it was written to FAIL the day
# that stopped being true. It did, on the merge that brought the arm in
# (bug-a-pxxsyswrite-has-no-wasm32-arm). That is the assertion-tracks-the-delta
# pattern working on its first real occasion, and it is the reason this
# replacement was written deliberately rather than noticed six weeks later.
#
# Now it is an ordinary differential, which is the strongest form available: no
# expected value is written down anywhere, so no part of the environment can
# supply the answer to both arms without the defect having to make them
# DISAGREE. The battery covers every helper with a field-width argument,
# because a dropped width is invisible in a single-value test.
"$root/compiler/pascal26" "$here/host_slice.pas" "$work/hs_native" >/dev/null
"$work/hs_native" > "$work/native.txt"

cat > "$work/speak.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
const sp0 = inst.exports.sp.value;
inst.exports.Speak();
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
// fd 1 only: anything the RTL sent to stderr is not this program's output.
process.stdout.write(h.text(1));
JS
node "$work/speak.js" "$work/w.wasm" > "$work/wasm.txt"
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  writeln matches the native build \
($(wc -l < "$work/native.txt") lines): literals, signed and unsigned, the"
  echo "..  64-bit extremes, char, boolean, and field widths"
else
  echo "FAIL writeln diverges from native"; exit 1
fi

# And the same module through node's real WASI, which routes fd 1 to the actual
# process stdout — an independent implementation of the interface, so a
# structurally wrong iovec that the hand-written host tolerates does not
# survive here.
cat > "$work/speakwasi.js" <<'JS'
const fs = require('fs');
const { WASI } = require('node:wasi');
const wasi = new WASI({ version: 'preview1', args: [], env: {},
                        returnOnExit: true });
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])),
  wasi.getImportObject());
// Started, then Speak called by hand — the same shape as speak.js above, so
// the two hosts are compared on the same export rather than on two different
// entry points. w.wasm is built with -dWASM_NOMAIN, so starting it runs an
// empty program body and stdout below is Speak's output alone.
wasi.start(inst);
inst.exports.Speak();
JS
node "$work/speakwasi.js" "$work/w.wasm" 2>/dev/null > "$work/wasi.txt"
if diff -u "$work/native.txt" "$work/wasi.txt" > /dev/null; then
  echo "ok  node's real WASI produces the same bytes on the real stdout"
else
  echo "FAIL node:wasi output differs from native:"
  diff -u "$work/native.txt" "$work/wasi.txt" | head -20
  exit 1
fi

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
wasi.start(inst);       // `_start`, the real command entry point
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

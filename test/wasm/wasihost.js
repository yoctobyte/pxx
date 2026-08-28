// Instantiate a wasm32 module against node's own WASI (preview1) and run it.
//
//   node wasihost.js <module.wasm> <sandbox-dir> [args...]
//
// WHY node:wasi RATHER THAN EXTENDING wasmhost.js. wasmhost.js is a shim this
// project wrote, and a shim written alongside the backend it tests agrees with
// that backend by construction — including where both are wrong. node's WASI
// is an independent preview1 implementation with a real filesystem and real
// preopens, so a disagreement between it and the native build is evidence
// about our backend rather than about our shim. It is also what makes the
// PAL's capability model testable at all: there is a directory to preopen, and
// paths outside it genuinely cannot be reached.
//
// The sandbox is preopened as ".", which is the shape `wasmtime --dir=.` gives
// and the one a relative path resolves against.
//
// $sp is checked after a NORMAL return only. A program that terminates does
// not unwind its frames on any target, so a stale $sp at proc_exit is correct;
// asserting balance there would fail every program that calls Halt.
const fs = require('fs');
const { WASI } = require('node:wasi');

const modPath = process.argv[2];
const dir = process.argv[3];
const wasi = new WASI({
  version: 'preview1',
  args: ['prog'].concat(process.argv.slice(4)),
  env: {},
  preopens: dir ? { '.': dir } : {},
  returnOnExit: true,
});
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(modPath)), wasi.getImportObject());
const sp0 = inst.exports.sp ? inst.exports.sp.value : null;
const code = wasi.start(inst);
if (code === 0 && sp0 !== null && inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.exitCode = code;

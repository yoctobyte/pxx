// wasihost.js plus a log line per path_open -- what the module ASKED the host
// for, in order, which is the one thing a trap inside the guest cannot tell you.
//
//   node wasitrace.js <module.wasm> <sandbox-dir> [args...]
//
// Written for the wasm-hosted compiler: `pascal26 t.pas` under WASI died with
// `memory access out of bounds` somewhere in the unit resolver, and the useful
// question was not which wasm function trapped (wasm-objdump answers that) but
// which FILE it had reached in the search chain. The trace shows the whole
// probe order -- t.pas, pxx.cfg, builtinheap.pas, then the .pp/.c/.h variants
// under each library root -- and the last line before the trap is the answer.
//
// Not part of check_all.sh: it is a probe, not an assertion. It wraps the
// import table rather than the module, so it needs no cooperation from the
// backend and stays correct as the backend changes.
const fs = require('fs');
const { WASI } = require('node:wasi');
const modPath = process.argv[2], dir = process.argv[3];
const wasi = new WASI({ version: 'preview1', args: ['prog'].concat(process.argv.slice(4)),
  env: {}, preopens: dir ? { '.': dir } : {}, returnOnExit: true });
const imp = wasi.getImportObject();
const w = imp.wasi_snapshot_preview1;
const orig = w.path_open;
let mem = null;
w.path_open = function (dirfd, dirflags, pathPtr, pathLen, ...rest) {
  const bytes = new Uint8Array(mem.buffer, pathPtr, pathLen);
  console.error('OPEN ' + Buffer.from(bytes).toString());
  return orig.apply(this, [dirfd, dirflags, pathPtr, pathLen, ...rest]);
};
const inst = new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(modPath)), imp);
mem = inst.exports.memory;
process.exitCode = wasi.start(inst);

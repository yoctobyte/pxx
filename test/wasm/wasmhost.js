// The minimal host every pxx wasm module needs, shared by every slice check.
//
//   const host = require('./wasmhost.js');
//   const h = host();
//   const inst = new WebAssembly.Instance(mod, h.imports);
//   h.bind(inst);                       // must precede any exported call
//
// A wasm module imports what its code can REACH, not what the program asks
// for, and the RTL's error reporters — PXXDivZero, PXXRangeError, PXXNilRef
// and the rest — all end in Halt. On this target Halt is WASI's proc_exit, so
// EVERY module imports proc_exit whether or not the program calls Halt. That
// is not an accident to design around: a program that can fault needs a way to
// exit, and a trap is not an exit — it loses the code.
//
// A host must supply every declared import or instantiation fails, which is
// why this exists as one file rather than six inline copies. The six copies
// were the alternative and they would have drifted; the first module to import
// something new would then have failed in five different ways.

class HostExit extends Error {
  constructor(code) { super(`proc_exit(${code})`); this.code = code; }
}

module.exports = function host() {
  const st = {
    mem: null,
    // Every fd_write call, decoded: { fd, bytes }. The harness decides whether
    // it wants the text, the fd, or merely the count.
    writes: [],
    exitCode: null,
    HostExit,
  };

  st.imports = { wasi_snapshot_preview1: {
    proc_exit(code) {
      st.exitCode = code;
      // Thrown rather than returned: proc_exit does not return, and a host
      // that let it would run the code after Halt.
      throw new HostExit(code);
    },

    fd_write(fd, iovs, iovsLen, nwritten) {
      const m = new DataView(st.mem.buffer);
      let total = 0;
      for (let i = 0; i < iovsLen; i++) {
        const p = m.getUint32(iovs + i * 8, true);
        const n = m.getUint32(iovs + i * 8 + 4, true);
        st.writes.push({ fd, bytes: Array.from(new Uint8Array(st.mem.buffer, p, n)) });
        total += n;
      }
      m.setUint32(nwritten, total, true);
      return 0;
    },
  }};

  st.bind = (inst) => { st.mem = inst.exports.memory; return inst; };
  st.text = (fd) => Buffer.from(
    st.writes.filter(w => fd === undefined || w.fd === fd)
             .flatMap(w => w.bytes)).toString('latin1');
  st.reset = () => { st.writes = []; };
  return st;
};

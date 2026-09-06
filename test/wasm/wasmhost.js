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

  // ---- the imports a module REACHES but this harness does not implement ----
  //
  // A module imports what its code can reach, not what the program calls, and
  // the sentence at the top of this file is the whole reason: instantiation
  // fails on a MISSING import, so one slice reaching a new corner of the RTL
  // breaks with a LinkError that says nothing about the program.
  //
  // That is not hypothetical. Building any program -dPXX_ALLOC_CENSUS pulls the
  // census reporter, which pulls the file layer, which lands fourteen more WASI
  // names in the import section — none of which the program calls. Before this
  // block, `check_nilpy_objlocal.sh` could not instantiate its own fixture.
  //
  // These return ERRNOS, they do not throw. A throw would be the tempting
  // choice — "nobody should be calling this" — and it is wrong twice over:
  // fd_prestat_get is called at startup by the preopen-enumeration loop, which
  // terminates ON EBADF and would instead take the harness down; and a stub
  // that cannot return leaves a future slice unable to reach the code past it.
  //
  // Every call is recorded in st.wasiStubs. A slice that needs one of these to
  // do real work should implement it here rather than locally — six inline
  // copies is the thing this file exists to prevent — and can assert on
  // st.wasiStubs meanwhile to prove its subject never depended on a stub.
  const EBADF = 8, ENOSYS = 52;
  st.wasiStubs = [];
  const stub = (name, errno) => (...args) => {
    st.wasiStubs.push({ name, args });
    return errno;
  };
  for (const [name, errno] of [
    ['fd_prestat_get', EBADF], ['fd_prestat_dir_name', EBADF],
    ['fd_read', ENOSYS], ['fd_seek', ENOSYS], ['fd_sync', ENOSYS],
    ['fd_close', ENOSYS],
    ['path_open', ENOSYS], ['path_unlink_file', ENOSYS],
    ['path_rename', ENOSYS], ['path_create_directory', ENOSYS],
    ['path_remove_directory', ENOSYS],
    ['clock_time_get', ENOSYS], ['random_get', ENOSYS],
    ['args_sizes_get', ENOSYS], ['args_get', ENOSYS],
  ]) {
    // Never shadow a real implementation above: this block only FILLS GAPS, so
    // adding a genuine fd_read up there silently wins and this loop skips it.
    if (!(name in st.imports.wasi_snapshot_preview1))
      st.imports.wasi_snapshot_preview1[name] = stub(name, errno);
  }

  st.bind = (inst) => { st.mem = inst.exports.memory; return inst; };
  st.text = (fd) => Buffer.from(
    st.writes.filter(w => fd === undefined || w.fd === fd)
             .flatMap(w => w.bytes)).toString('latin1');
  st.reset = () => { st.writes = []; };
  return st;
};

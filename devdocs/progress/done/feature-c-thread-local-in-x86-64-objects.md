---
track: C
tags: [c, tls, object, threads, rump, netbsd, silent-miscompile]
prio: 10
type: feature
blocked-by: []
summary: "A C `__thread` in an --emit-obj x86-64 object had ONE copy shared by every thread (rump gap S8; only a warning). It is real ELF TLS now: each variable is its own .tdata.<name> section (SHF_TLS) with an STT_TLS symbol, reached through fs like gcc's code: local-exec for a `static`, initial-exec otherwise. rump's curlwp is `__thread`, and the shared copy panicked at boot."
status: done
owner: claude-dupwt
---

# C `__thread` in x86-64 objects is ELF TLS

pxx's thread-local storage is its own gs-based block, which pxx's entry point
installs. An object has no pxx entry point, so `TryAssignThreadVarStorage`
refused (TLSREFUSE_NOINSTALL). The C frontend then degraded as designed: one
shared copy plus a warning.

rump builds with `-DRUMP_CURLWP=RUMP_CURLWP___THREAD`, so `curlwp_storage` is
`__thread`. The first pxx-built librump to link
(buildrump `tests/init`) aborted at boot. The second thread's
`rump_lwproc_curlwp_set` found the first thread's lwp and failed
`KASSERT(curlwp == NULL)`, and the panic path then died in `mutexexit`.

## Fix

The program that links the object has an ELF libc or kernel that sets `fs`,
which is what gcc's objects use. So in an x86-64 object (`--emit-obj`, not
`--shared`):

- **Storage.** The variable becomes its own `.tdata.<name>` cut. This reuses
  the section-attribute path, so an initialiser is baked into the bytes every
  thread's copy starts from. The section is flagged WAT, and the symbol (local,
  global or UND) is STT_TLS.
- **Access.** `EmitElfTlsAddr` produces the address. A reference is rewritten
  in `ThreadVarRewriteRange` (scalars), or redirected in `IRAppend` (arrays and
  structs, `CElfTlsByAddress`), into `IR_TLSBASE` with a negative ival naming
  the symbol:
  - `static` (always defined here), local-exec:
    `mov rax, fs:[0]; lea rax, [rax+x@tpoff]`, using R_X86_64_TPOFF32 against
    the cut's section symbol plus an addend.
  - Otherwise initial-exec: `mov rax, [rip+x@gottpoff]; add rax, fs:[0]`,
    using R_X86_64_GOTTPOFF against the symbol. ld relaxes it in an executable.
  - The site kind travels in `GlobFixTls`, parallel to GlobFix; dce.inc
    carries it.
- **Limit.** A hosted object (no `CStaticDataMode`) whose `__thread` has an
  initialiser keeps the old shared copy and the warning. Its initialiser would
  be an init-thunk store that only the main thread's copy sees.

Neither access model is valid in a `dlopen()`ed shared object (that needs
general-dynamic). `--shared` is not routed here.

## Proof

`test/c_thread_local_object.c` covers a global, an initialised `static`, an
array, a struct, a `static` pointer to another thread-local, and an `extern`
defined by the gcc main. Four threads each count to 2000 in their own copy,
and the addresses differ. It matches gcc's object exactly as an
`-O2 --freestanding` object (initialiser baked) and as a hosted object with
`-DTL_NO_INIT`. Rows: c_tlsobj26_f, c_tlsobj26.

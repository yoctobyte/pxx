---
summary: "FIXED 2026-11-20 (claude-dupwt) for item (1), the --system-libs executable on x86-64 and i386: pthread_create is routed through palhostthread (see the bottom section); (2) and (3) below stay open. RE-MEASURED 2026-11-19 (rd): the silent half below is FIXED. Statically linked, an initialised scalar, an array, a struct and a function-scope static `__thread` are per-thread and initialised from the image on x86-64, i386, aarch64 and arm32 (gcc's output; test/c_tls_threads_libc_warns.c). What still shares one copy: (1) a DYNAMIC binary (--system-libs) whose threads the loaded libc starts. A C program there calls the host pthread_create directly and its threads inherit the creator's block. On x86-64 this was SILENT until 2026-11-19 and now warns; aarch64/arm32 warned already. Fix: route those threads through PxxPthreadStart, or emit real ELF TLS (PT_TLS + fs-relative local-exec) in pxx's own dynamic link. (2) --emit-obj/--shared without --system-libs (warns; with --system-libs objects carry real ELF TLS since 877d42f8b5). (3) targets with no block install (riscv32, xtensa: no threads). The old text below is the history."
type: bug
track: C
prio: 40
status: open
created: 2026-09-16
found-by: frankb-56
tags: [tls, threads, c-frontend]
blocked-by: []
---

# Thread-local storage still shares one copy off x86-64

## Why this ticket exists at all

[[bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared]]
was closed by giving `__thread` real per-thread storage on x86-64 scalars. That
fix is a **strict improvement with no regression anywhere** — every program that
compiled before still compiles, and every program that was correct before is
still correct.

**"No regression anywhere" is true and it is not the whole finding.** An
exculpation needs an owner for the residual question, and the residual is a
population that is still served a wrong answer. This ticket is that owner, so
the claim does not end at a true sentence that reads like an all-clear.

## The population still affected

A **multi-threaded** C program using `__thread`, where any of these holds:

| condition | why the mechanism cannot serve it |
| --- | --- |
| target is not x86-64 | the per-thread block is installed by `arch_prctl(ARCH_SET_GS)` in the clone stub; aarch64/arm32 have a *readable* thread register (`tpidr_el0`, `tpidruro`) and no way to SET one yet |
| the variable is an array | several paths reach an array through its SYMBOL (bounds, handles, element type) and a thread-local reference is rewritten to a pointer dereference before they see it |
| the variable is a managed or aggregate type | needs per-thread init/final at thread start and exit; no thread hook exists |
| `--emit-obj` / `--shared` | no ELF entry point, so nothing installs the block |
| **function scope** (`static __thread int t;` inside a body) | the fix hooks `ParseCGlobalVarDecl`; a local declaration never reaches it. **Warns since 2026-09-19 (`TLSREFUSE_FUNCSCOPE`); still shares.** |

In every one of these the declaration compiles to **one shared `.bss` object**,
exactly as it did before the fix, and a warning naming the specific reason is
the only thing between that program and a wrong answer.

**FIXED 2026-09-19 — THE FUNCTION-SCOPE ROW WAS THE ONE THAT WARNED NOTHING AT
ALL, AND NOW WARNS.** It gained `TLSREFUSE_FUNCSCOPE`, a sixth reason that is
not an answer from the allocator but the absence of a question: the block-scope
storage-class loop consumed the qualifier and recorded only `static`, so no idx
and no reason ever existed. **The sharing is unchanged** — see
`feature-c-a-function-scope-thread-local-gets-real-per-thread-storage` for why
giving it real storage is blocked on the area sizing rather than merely undone.
The paragraph below is the original finding and is kept as the record of what
was true before; read it in the past tense.

**THE FUNCTION-SCOPE ROW WAS THE ONE THAT WARNED NOTHING AT ALL.** The fix hooks
the file-scope declaration parser, so a `static __thread int t;` inside a body is
never seen by it — and the warning it replaced lived in the TOP-LEVEL walk, so
that shape never warned before this change either. **No regression, and it is now
the only silent member of the family**, which is exactly the property the parent
ticket was filed about.

**SCOPING CORRECTED 2026-09-16 (frankuser), and the correction matters because
the old wording misrouted.** This ticket's population is *"multi-threaded C
off x86-64"*, and function scope was listed inside it — but function scope fails
**on x86-64, with one thread**, so a reader filtering on either qualifier would
skip it. That was true when written for a different reason than assumed: what
made it fail single-threaded was **not** thread-local storage at all, it was the
block-scope `static` being silently discarded when `__thread` stood between it
and the type, which produced a wrong value with no threads anywhere near it.
**That bug is fixed** —
[[bug-c-a-block-scope-static-is-silently-dropped-when-a-thread-storage-class-precedes-the-type]].

**So what remains at function scope is SHARING ONLY**, and it now genuinely does
belong to this ticket's population: storage is correct, `static __thread int t;`
counts 1, 2, 3 exactly as gcc does single-threaded, and every thread still uses
the one copy. Whoever takes this should still do function scope FIRST — it is
the smallest of the five and the only one where a user gets no signal at all.

## Why it warns instead of refusing, and why that is not being revisited here

`__thread` **compiles today**. For a single-threaded program one copy shared IS
one copy per thread, so those programs are correct, and refusing would break
working programs to protect broken ones. The parent ticket prescribed refusal —
written before x86-64 worked, i.e. a prediction — and re-derived against the
built thing the prescription does not survive. Pascal's `threadvar` refuses
because it has never compiled at any scope and so has no population to break.

That reasoning is settled and this ticket is not a request to revisit it. What
is open is **closing the gap**, not changing what happens while it is open.

## What would close it

Any one of these shrinks the population; none is required for the others:

1. **A settable thread register on aarch64/arm32** — the blocker named by the
   refusal text itself. Closes the largest slice.
2. **Arrays** — the TLS user area already fits one; the work is teaching the
   symbol-reaching paths about a rewritten reference.
3. **`--emit-obj`/`--shared`** — needs an entry-point-independent way to install
   the block, and interacts with the GS-vs-psABI fork: GS-relative serves
   pxx-compiled code and does NOT interoperate with TLS relocations in a
   gcc-built object.

## Acceptance

**Assert the RELATION, not a per-target constant** — two threads writing and
reading the same `__thread` variable must never see each other's value — so a
row carries no expected width and cannot pass by matching a default.

**A row per target with an object writer**, because TLS is emitted per backend:
one green on x86-64 closes nothing. `test/c_thread_local_is_per_thread.c` is the
x86-64 row and is the shape to copy; its six assertions and, in particular,
which two of them (`zeroed-on-entry`, `main-copy`) survive serial execution are
documented in the file.

## 2026-09-24 (frankS): aarch64 and arm32 get a block, in a static binary

What landed:
- The entry code installs the main block: tpidr_el0 on aarch64; TPIDRURO via
  the set_tls syscall on arm32. It does so only when the register reads 0 at
  entry, which is true of a static binary. A dynamic one arrives holding
  glibc's TCB.
- The clone leg carves a zeroed block off the child's stack. The child
  installs it only when the parent's register holds a pxx block, recognised by
  slot 0 holding its own address.
- IR_TLSBASE uses the same recognition and falls back to the main block
  otherwise. So a dynamic binary gets one shared copy, which is the old
  behaviour, and never writes into glibc's TCB.
- The ELF writer refuses a dynamic binary for Pascal `threadvar` and
  `__pxxTlsBase`, which never compiled shared. For C it warns only when the
  program creates threads, because errno.h declares errno `__thread` and
  refusing would stop every C program that links a shared library.

Measured with test/test_a_threadvar_is_per_thread.pas and
test/c_thread_local_is_per_thread.c, both THREADVAR/C THREAD-LOCAL OK on
aarch64 and arm32 under qemu, plus c_errno_is_per_thread.c. Positive control:
the same compiler with the child's install replaced by a nop gives
zeroed-on-entry=0/4 and main-copy=103 on both targets and both fixtures.
Dynamic probes (a C program importing a Pascal unit with an `external
'libc.so.6'`; readelf shows INTERP) run on both targets, and pthread_self in a
dynamic Pascal program stays in the mmap range, not pxx's BSS, so glibc's
register is untouched. Rows are in test-threads.

Found on the way, NOT fixed here: an initialised C `__thread int x = 5;` reads
0 in a child thread (gcc: 5) on every target. The initialiser is a startup
store into the main thread's block, and a new block starts zeroed.

## i386, 2026-09-27

Case (1) no longer includes i386. The block goes in `fs` through
`set_thread_area` (glibc's i386 TCB is on `gs`, so it is installed in dynamic
binaries too): the entry code allocates the GDT TLS entry, the clone leg and
palthread's `PxxPthreadStart` re-point the inherited entry at the child's own
block, and `TLS_SLOT_FS_ENTRY` carries the entry number to the trampoline.
Measured before, on i386: `c_thread_local_is_per_thread` kept=1/4
main-copy=103, the initialiser fixture grandchild-x=50, errno-crosstalk=1, and
`threadvar` refused. After: all gcc-equal, natively and under qemu-i386, on
the clone route and the libc-linked pthread route (test-threads rows
`i386/*26_i386`).

## Update 2026-11-14: case (3) closed for C

A C `__thread` array or struct (any non-managed record; C has no managed
types) gets real per-thread storage, with initialisers, on all four targets:
feature-c-thread-local-arrays. The (1) target, (2) dynamic-binary, (4)
--emit-obj/--shared and (5) function-scope cases are unchanged.

Also 2026-11-14: case (5), function scope, is closed. A `static __thread` in
a function body gets per-thread storage, falling back to the shared copy with
a warning only when it cannot be placed:
feature-c-a-function-scope-thread-local-gets-real-per-thread-storage. Still
open here: (1) targets with no block, (2) dynamic aarch64/arm32 binaries, and
(4) --emit-obj/--shared.

## Re-measured 2026-11-19 (rd)

Test: one program, four `__thread` shapes, a pthread that reads and then
writes them, and main reading them again afterwards. Compared with gcc's
output.

| build | x86-64 | i386 | aarch64 | arm32 |
|---|---|---|---|---|
| static, --threadsafe | same as gcc | same | same | same |
| --system-libs (dynamic) | **shared, was silent** (now warns) | -- | shared, warns | shared, warns |

In the dynamic case on x86-64, the thread is libc's: `U pthread_create` in
the binary. It inherits the creator's gs block. af94ac7dba adopts a fresh
block for such a thread only at a Pascal `try` entry, so a C `__thread`
access never adopts one. ResolveSynthImportLibraries now warns when an
x86-64 dynamic binary has per-thread storage (TlsUserUsed > 0) and imports
pthread_create or thrd_create. test-core row: c_tls_threads_libc_warns.

The fix, not done here. Either:
- route a --system-libs C program's pthread_create through pxx's start
  trampoline (PxxPthreadStart), which installs and initialises a block; or
- give pxx's own dynamic link real ELF TLS: PT_TLS, .tdata/.tbss, and
  fs-relative local-exec accesses, so glibc builds every thread's block.
  The object path already emits this (ac091638d7).


## Fixed 2026-11-20 (claude-dupwt): the --system-libs executable, item (1)

A C executable whose pthread_create is the host libc's (`--system-libs`, or
`=pthread`) on x86-64 or i386 now has `pthread_create` predefined to
`__pxx_host_pthread_create` (cpreproc.inc, CHostPthreadRoute). The host
header's prototype and every call bind to that name. It lives in the new unit
lib/rtl/palhostthread.pas, which ParseCProgram pulls for such a program. It
is not palthread, because palthread compiles __pxxclone and so needs
--threadsafe. The wrapper calls the real pthread_create with a trampoline,
which installs a block of the thread's own (PxxThreadBlockInstall, moved out
of palthread's PxxPthreadStart, which now calls it too). It then runs the C
start routine and returns its value to pthread_join. The weak libc imports
`pthread_create`/`pthread_join` are now declared once, in palhostthread.

test/c_tls_threads_libc_warns.c (initialised scalar, array, struct,
function-scope static) prints gcc's output when built `--system-libs` and
`--threadsafe --system-libs` on x86-64, and `--target=i386 --system-libs`.
latest-f784b38446 printed `main 9 30 50 14` (shared) on both targets, and
on i386 it did not even warn. The `--threadsafe` build also needed
bug-c-the-c-driver-never-allocates-the-heap-lock-word (done, same commit).

Still open:
- (2) `--emit-obj`/`--shared` without `--system-libs`, and (3) riscv32/xtensa,
  as before.
- thrd_create: glibc's calls its own pthread_create internally, so it is not
  routed and still warns.
- A thread that leaves by pthread_exit, or is cancelled, skips the munmap of
  its block (it leaks). The block is unmapped when the start routine returns,
  so a pthread_key destructor written in pxx C that touches a thread-local
  after that runs on no block. The Pascal pthread route has the same two
  properties.

Verified: gate quick GREEN; test-threads and test-c-conformance 0 failures; test-core: its only reds were two --threadsafe objects linking duplicate palhostthread symbols (c_objth/c_objth_g), fixed by making the unit a weak runtime unit like palthread (ObjProcIsBuiltinRtl); both rows then pass.

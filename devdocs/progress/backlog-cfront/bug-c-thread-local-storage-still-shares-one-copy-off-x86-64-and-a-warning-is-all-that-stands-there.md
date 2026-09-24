---
summary: "STATE 2026-09-24 (frankS). A file-scope SCALAR `__thread` gets real per-thread storage wherever TargetHasTlsBlock holds and the binary installs a block: x86-64 (gs) always, and aarch64 (tpidr_el0) and arm32 (TPIDRURO, set_tls) in a STATIC binary. It still gets ONE shared copy in these cases: (1) a target with no block install (i386; riscv32 and the rest have no threads); (2) a DYNAMIC binary on aarch64/arm32, because glibc owns the one thread register, so reads fall back to the main thread's block and a link-time warning fires when the program also creates threads; (3) an array or a non-scalar type; (4) --emit-obj/--shared, which have no entry point to install a block; (5) function scope, which is feature-c-a-function-scope-thread-local-gets-real-per-thread-storage. Each of these warns. The pieces that would close each case: an i386 set_thread_area port; glibc ELF TLS (PT_TLS) for dynamic binaries; symbol-path support for arrays; per-thread init/final hooks for managed types."
type: bug
track: C
prio: 40
status: backlog
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

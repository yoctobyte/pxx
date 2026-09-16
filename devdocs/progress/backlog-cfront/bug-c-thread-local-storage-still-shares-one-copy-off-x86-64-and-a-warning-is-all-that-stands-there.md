---
summary: "The RESIDUAL left by the __thread fix: on x86-64 with a file-scope scalar, `__thread` gets real per-thread storage; everywhere else — any other target, an array, --emit-obj/--shared, and FUNCTION SCOPE — it still compiles to ONE SHARED object and only a warning says so, except at function scope where there is NO warning at all. Not a regression; this is byte-identical to the behaviour before the fix. NOTE the function-scope row is about SHARING ONLY: the separate bug that made it a wrong value single-threaded (the `static` being dropped) is fixed and is bug-c-a-block-scope-static-is-silently-dropped-when-a-thread-storage-class-precedes-the-type."
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
| **function scope** (`static __thread int t;` inside a body) | the fix hooks `ParseCGlobalVarDecl`; a local declaration never reaches it |

In every one of these the declaration compiles to **one shared `.bss` object**,
exactly as it did before the fix, and a warning naming the specific reason is
the only thing between that program and a wrong answer.

**THE FUNCTION-SCOPE ROW IS THE ONE THAT WARNS NOTHING AT ALL.** The fix hooks
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

---
slug: decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit
track: U
prio: 55
type: decide
status: backlog
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "A pxx --emit-obj object exports its ENTIRE runtime -- 288 weak FUNC symbols for a two-function C translation unit -- and per-object DCE therefore cannot prune it: measured, an object keeps 529 of 804 bodies where the same code as an executable keeps 78. Pruning it changes the object's LINK SURFACE (the symbol goes, not just the bytes), which is a semantic change one existing test asserts against. The fork: is an object a self-contained runtime that anything may link against, or a translation unit whose runtime is an implementation detail? Both are coherent; they differ on what a second object may assume."
---

# Is a pxx object a self-contained runtime, or a translation unit?

## The fork

`ObjProcIsExported` is `ProcCdecl and not ProcCStaticLink`, and **every crtl
routine satisfies it**, because crtl is C and C functions are cdecl and
non-static. So an object's export surface is its whole runtime.

That was free until a pass started deleting things. Measured at `60edd4853`
(one C TU, two exported functions, using `snprintf`/`malloc`/`strlen`):

| | bodies live | bytes |
| --- | --- | --- |
| `--emit-obj --dce` | 529 of 804 | 291416 |
| the same code as an executable | 78 of 805 | 78488 |

6.8x, and it is entirely the root set. Full measurement in
[[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]].

## The two answers

**A — self-contained runtime.** An object carries a complete crtl and exports
it weakly. Anything can link against it and get a working `malloc`. This is
what ships today, and `test-emit-obj` block 4b-septies asserts it: two objects
share one heap, one `errno` and one `optind` against a gcc oracle. Cost: every
object is ~335KB of which the user wrote 200 bytes, and 41 busybox TUs are
13.7MB. Per-object DCE cannot help, ever, under this answer.

**B — translation unit.** An object keeps the runtime IT reaches; the rest is
an implementation detail and its symbols go. ~78KB per TU on these numbers, so
busybox lands in single-digit MB before any cross-object work. This is the
semantics option (1) of the parent ticket (a `libcrtl.a`) chooses deliberately
— B is the same change arriving without the archive that makes it deliberate.

## What decides it

**What may a SECOND object assume about the first?** Under A, that any crtl
entry point is there. Under B, only that the object's own declared surface is.
A gcc-compiled TU linking a pxx object is the case that matters: under B it
gets glibc's `malloc` for anything the pxx object did not itself use, and that
is either obviously right or a silent split-runtime bug depending on which
answer we hold.

Note 4b-septies is probably NOT the blocker it looks like: it pins DATA symbols
(one heap, one `errno`, one `optind`) and code DCE does not touch `.bss`. That
is reasoning, not a measurement — check it before quoting it either way.

## Recommendation

**B, gated behind `--dce` only** — so nothing changes for a default object and
the reduction is something a busybox build opts into. It keeps A available and
makes the surface change follow an explicit flag rather than a release. The
mechanism exists and is small: `ParseCProgram` already holds `crtlStart`, the
token index the crtl pull begins at, and nothing carries that onto the
`Procs[]` row.

---
track: U
prio: 55
type: decide
status: open
owner: ""
created: 2026-09-06
found-by: frankC
tags: [tls, threads, abi, emit-obj]
blocked-by: []
summary: "pxx installs its per-thread block on GS (thread_emit.inc:142, `GS, not fs: fs belongs to libc, and a pxx program may link one`) and the x86-64 psABI puts ELF TLS on FS. Measured 2026-09-06: a pxx-native thread gets a DISTINCT non-zero GS base (main 42D110 in .bss, child 7BDB21FF7A80 off its own stack) with FS 0 in both, so the mechanism works -- for pxx-compiled code. The fork is what happens at the boundary: GS-relative thread-locals cannot be reached by TLS relocations in a gcc-built object, and --emit-obj exists precisely to be linked into foreign programs. Nobody has ruled on this and bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared cannot be implemented without the ruling. A second measured fact bears on it: a thread pxx did NOT create inherits the parent's GS base (glibc pthread_create gives main and child the identical 4298F0), so any GS scheme is also deciding what a foreign-created thread gets."
---

# GS-relative TLS vs the FS-relative psABI

## The fork

`__thread` needs per-thread storage. pxx has a per-thread block and it is on
**GS**. Standard x86-64 ELF TLS is on **FS**. Which one do pxx's thread-locals
use, and what do we promise at the boundary?

## What is already settled, and by whom

`thread_emit.inc:142` chose GS deliberately and stated the reason in the code:
*"GS, not fs: fs belongs to libc, and a pxx program may link one."* That is a
good reason and this ticket is not reopening it for pxx-internal use. Measured
2026-09-06 (with a sentinel control that separates "base is 0" from "arch_prctl
never ran"), a pxx-native `BeginThread` thread gets a distinct non-zero GS base
while FS is 0 in both threads. **The mechanism works.**

## The options

**1. GS-relative, pxx-only.** Thread-locals work in pxx-compiled code. An
`--emit-obj` object's `__thread` variables are NOT reachable by a gcc caller's
TLS relocations, and a gcc object's `__thread` is not reachable by ours. State
it as a documented boundary.

- cheapest, consistent with the choice already made, and needs no FS handling
- but `--emit-obj` is *for* linking into foreign programs, which is where the
  limitation lands hardest

**2. FS-relative, psABI-conformant.** Interoperates. Conflicts with the reason
GS was chosen: a pxx program that links libc has FS owned by that libc, and the
two would fight over it.

**3. Both, by output mode.** GS for a standalone pxx program, FS/psABI under
`--emit-obj` and `--shared`. Correct at both boundaries and the most work —
two relocation models and two accessor shapes.

## Recommendation

**Option 1 for now, with the boundary written down**, and option 3 named as the
upgrade path if a real consumer appears. The deciding question is whether
anyone actually links a pxx object containing `__thread` into a gcc program —
if nobody does, 2 and 3 buy nothing and cost a fight with libc over FS.

**What would settle it is a real consumer, not an argument.**

## A PROOF OF CONCEPT THAT FITS IN THE SLACK IS NOT A SMALLER VERSION OF THE FEATURE

Framing owed to frankA, who says they would have walked into it. The existing
per-thread block is exactly full — 144 slots, 0..12 taken, the heap magazine at
16..79 and 80..143 — leaving **three**. Three is enough to demonstrate
`__thread` working on one variable and nothing like enough for the feature,
**and a demo is how a design gets ratified.**

So a working one-variable proof would be evidence for the wrong proposition: it
would show that GS-relative access works (true, and not the open question)
while saying nothing about allocation, which is the part that has to change.
Whoever implements this must size the area first and demonstrate second.

Same shape as the discriminating-fixture problem on the layout ticket next door:
`{int a; double y}` "works" under both candidate rules and therefore separates
neither. **A fixture that fits the slack cannot test the thing the slack is
hiding.**

## And a second thing to rule on at the same time

A thread pxx did NOT create **inherits** the parent's GS base rather than
getting its own. Measured: glibc `pthread_create` gives main and child the
identical `4298F0`, because GS base is inherited across `clone` and such a
thread never passes through pxx's stub.

So under any GS scheme, a foreign-created thread silently shares the creator's
thread-locals. That is the hazard the clone stub's own comment cites as its
reason for installing GS first — *a valid-looking pointer into someone else's
storage*, not a null you could test for. Options are to detect it and refuse,
to install lazily on first access, or to document it. **Whichever way this
fork goes, that question is part of it** and should not be answered separately
by whoever writes the code.

Blocks [[bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared]].

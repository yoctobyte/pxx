---
track: U
prio: 65
type: decision
status: new
blocked-by: []
owner: ""
summary: "The fix for bug-c-a-c-function-s-calling-convention-depends-on-the-target has two shapes and they differ in principle, not just size. (A) A C function ALWAYS uses the C ABI and every call site marshals it, including intra-C calls. (B) A C function uses the C ABI only when its unit belongs to a PASCAL program, keeping pxx's internal convention for pure C programs. B is smaller and safer for the C corpus; it also makes the convention depend on WHO INCLUDED THE UNIT, which is a second axis of exactly the disease the ticket exists to remove."
---

# Does a C function always use the C ABI, or only when a Pascal program uses it?

Escalated rather than guessed: this is a design fork that cannot be settled from
the code, and the two answers are materially different work with different risk.

## What is established (measured, not argued)

`CProgramMode` does **not** mean "this is a C program". It means *"the source in
front of me is C"* — `ParseCUnit` sets it exactly as `ParseCProgram` does, so it
is True while compiling a C translation unit that a **Pascal** program `uses`.
Found by frankA with a probe on the prologue gate; confirmed independently here
with no compiler change, by calling a `double`-taking C function *from other C
code inside a Pascal-used unit*: **1000/1000 on all five targets**, i.e. those
intra-C call sites and the positional prologue agree today.

That is why the four positional prologue arms in `cparser.inc` are load-bearing:
inside C source the call sites choose their convention through the seven
`ProcCdecl[procIdx] and (not CProgramMode)` guards, which are False there, so
caller and callee agree positionally. Deleting the arms moves only the callee
and breaks every C→C call —
[[bug-a-a-c-mode-function-took-the-cdecl-call-path-on-aarch64-and-arm32]] run
backwards, and measured as exactly that: control PASS → FAIL on aarch64,
COMPILE FAIL on arm32, SEGFAULT on i386.

## Option A — a C function always uses the C ABI

Prologue, all seven caller guards, and the return-side counterpart move together.
`ProcCdecl[procIdx]` alone answers "is this proc reached by the C ABI?" — which
is **requirement 3 of the parent ticket**, in one place, for good.

- **For:** one answer, everywhere. Removes the axis the ticket was filed about
  instead of adding another. A C function reached from anywhere — Pascal, C, a
  function pointer, a future frontend, a gcc-built caller through a callback —
  is one thing.
- **Against:** every pure C program on i386/arm32/aarch64 changes convention. The
  corpus is large (lua, sqlite, quickjs, zlib, busybox) and self-consistency
  today means the change is invisible to most tests until it is not. Bigger
  behavioural blast radius, and the cross suites cannot prove it (they are
  self-consistent before *and* after — see the parent ticket).

## Option B — the C ABI only for a C unit a Pascal program uses

The discriminator becomes "this C unit belongs to a Pascal program", read by the
prologue **and** the seven caller guards together, so intra-unit C→C calls move
with it.

- **For:** far smaller. Pure C programs keep the convention they have and the
  corpus is untouched. Fixes the shape that is actually broken today — a Pascal
  caller meeting a C callee.
- **Against:** a C function's ABI now depends on **who included its unit**. The
  parent ticket's title is *"a C function's calling convention depends on the
  target"*; this replaces one context axis with another, and requirement 3 —
  a single place that answers the question — is not met, it is re-parameterised.
  A C unit used by both a Pascal program and a C program would compile to two
  different ABIs, and nothing in the source says so.

## Recommendation

**A**, but not confidently, and the pragmatic case for B is real. The parent
ticket exists because "it depends" was the defect; B keeps "it depends" and only
changes what it depends on. Against that: A's blast radius lands on the corpus
that pays this project's rent, and B fixes every shape a user can reach today.

A middle path worth considering if A is too big at once: take **B as a staged
step with A named as the destination** — but only if the provenance gate is
written as a single named predicate rather than a condition spelled out at eight
sites, since eight spellings is how the original defect got to strike three.

## Who is blocked

[[bug-c-a-c-function-s-calling-convention-depends-on-the-target]] (frankC,
blocked) and
[[bug-a-the-shared-cdecl-spill-arm-cannot-yet-do-the-job-it-would-be-given]]
(frankA, in progress — currently implementing B).

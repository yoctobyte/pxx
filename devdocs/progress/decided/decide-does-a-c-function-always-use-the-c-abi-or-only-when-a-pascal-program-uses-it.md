---
track: U
prio: 65
type: decision
status: decided
blocked-by: []
owner: ""
summary: "RULED 2026-08-31 by the owner: NEITHER YET -- keep the landed gate (option B, b4ff9adea) and DEFER the A/B choice on a named trigger, because nothing in the system can currently observe the answer. Three findings changed the question. (1) B is already BUILT and green; the ticket's 'frankA is currently implementing B' is stale -- that ticket was the spill-arm PREREQUISITE and is done. The choice is now ONE CLAUSE in CProcUsesCAbi (symtab.inc:11599), not two bodies of work. (2) x86-64 NEVER DIVERGED -- it has always used EmitParamSpillsForTarget, so only i386/arm32/aarch64 are in scope. (3) The owner's framing: ABI matters only at BOUNDARIES, and internally we may do as we see fit -- a third reading the ticket never listed. We do cross boundaries today (DT_NEEDED imports; GTK calls our callbacks via gtk3.pas:47) but ONLY on x86-64, the target with no divergence, so that evidence proves the machinery and settles nothing. TRIGGER: meta-a-pxx-produces-linkable-code / feature-a-a-general-x86-64-relocatable-object-writer (re-priced to 80). When a gcc-built caller can link a pxx object on i386, this becomes a measurement; decide it then, in one clause."
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

---

# RULED 2026-08-31 — neither yet, and here is what would settle it

Owner's call. **Keep the landed gate; defer A vs B on a named trigger.**

## Why the question changed shape

**1. Option B is already built and green.** The "Who is blocked" section above
says frankA is *"in progress — currently implementing B"*. That is stale in two
ways: the ticket is `done` (`b4ff9adea`, 2026-08-30), and it was the **spill-arm
prerequisite**, not B — three gaps in `EmitParamSpillsForTarget` (aarch64
by-value `Single`, i386 with no float classification at all, arm32 unable to
compile a varargs TU).

The discriminator landed as the single named predicate the middle path required,
`compiler/symtab.inc:11599`:

```pascal
Result := (procIdx >= 0) and ProcCdecl[procIdx] and
          ((not CProgramMode) or CUnitOfPascalProgram);
```

Option A is **deleting the third line.** One definition, nine read sites across
four backends, one spelling. So this is no longer *"materially different work
with different risk"* — that framing predates the landing.

**2. x86-64 never diverged.** The positional prologue arms are
**i386 / arm32 / aarch64**; x86-64 *"has always used"* `EmitParamSpillsForTarget`,
the cdecl arm. Only three targets are in scope, and the one everybody develops on
is not among them.

**3. The owner's framing — a third reading the ticket never listed.** *"cdecl is
only needed for exported functions? internally we can do as we see fit?"* That is
right in principle: ABI binds at **boundaries**. Under it, both A and B argue
about the convention for calls that never cross one, and the C ABI is owed at
`ProcExternal`, at exports, and at escaping function pointers — nowhere else.

## Why it is DEFERRED rather than answered

The argument for A was that it is externally verifiable: a C function on the real
C ABI can be checked by a foreign caller, whereas B leaves pure C programs in a
private convention nothing outside pxx can ever check — the exact condition that
let this bug live on three targets.

**That argument is currently circular.** We cannot link a pxx object against a
gcc-built caller on any of the three targets: `--emit-obj` writes general objects
for xtensa/riscv32 only, and `--shared` is `.asm`-frontend only. So A's advantage
is unrealisable and A's risk is unmeasurable — the cross suites are
self-consistent before *and* after, which is why they proved nothing the first
time.

**And the boundary we DO cross does not help.** `elfwriter.inc` emits
`DT_NEEDED`/`dynsym`/GOT-indirect calls, and GTK really does call our callbacks
(`lib/pcl/gtk3.pas:47` → `g_signal_connect_data`). But that runs on **x86-64**,
the target with no divergence. Working callbacks prove the machinery and say
nothing about i386/arm32/aarch64. Correct about something else.

## The trigger, and the cost of waiting

Trigger: [[meta-a-pxx-produces-linkable-code]], concretely
[[feature-a-a-general-x86-64-relocatable-object-writer]], re-priced 30 → 80 by
the owner in the same session. When a gcc-built caller can link a pxx object on
i386, A vs B stops being a matter of principle.

Cost of waiting: **one clause.** The done ticket built it that way on purpose —
*"if Track U answers 'always the C ABI', it changes in one function body."*

## What is NOT deferred

The **callback hazard** under the boundary reading, which no option here covers:
a function pointer escaping to foreign code must be cdecl, and `ProcExternal`
marks a *callee* as foreign, not a *pointer* as escaping. Unreachable today on
the three divergent targets — and reachable the moment the object writer lands,
which is precisely when nobody will be looking. It belongs in the object-writer
work, not here.

*Findings measured 2026-08-31 by frank-user; ruled by the owner in the same
session.*

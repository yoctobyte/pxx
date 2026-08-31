---
track: U
prio: 65
type: decision
status: decided
blocked-by: []
owner: ""
summary: "TRIGGER FIRED 2026-08-31 -- the measurement is IN and it says OPTION A; awaiting the owner's ruling, which is one clause. Ruled that morning as NEITHER YET, deferred on a named trigger (a gcc-built caller linking a pxx object on i386), because nothing could observe the answer. The i386 object writer landed and the trigger fired the same day. Measured, same compiler / writer / target / gcc -m32 -no-pie caller, differing only in CProcUsesCAbi: where it is FALSE (a standalone C unit -- option B's behaviour) two integer args arrive REVERSED (i_ii(1,2) = 21 = 2*10+1) and every double arg and return is -nan; where it is TRUE (Pascal cdecl, same signatures) all four are correct. x86-64 is correct throughout, as expected -- it never diverged. THREE LIMITS: this measures boundary BEHAVIOUR and not the COST of flipping (the seven `ProcCdecl and (not CProgramMode)` call-site guards are a different expression from CProcUsesCAbi and must move with the callee, unverified here); arm32 and aarch64 are still unmeasurable, having no object writer; and it is NOT confounded by bug-a-i386-clobbers-ebx-across-a-cdecl-exported-function, which sits on the option-A side."
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

## TRIGGER CORRECTED 2026-08-31 — the x86-64 writer cannot settle this

`feature-a-a-general-x86-64-relocatable-object-writer` **landed the same day**
(`41045d7b4`, resolve `ed5a62e4d`). A pxx object now links under gcc, clang and
tcc — verified independently here: `pxx_add` exports as a global `T` symbol and
all three linkers produce a binary printing `42`; the `-pie` control fails as
designed.

**It does not trigger this decision, and naming it was my error.** frankC caught
it: this ruling's own finding (2) says **x86-64 never diverged** — it has always
used `EmitParamSpillsForTarget`. So an x86-64 object exercises the ABI on the one
target where both options agree. It proves the machinery and settles nothing,
which is exactly what this ruling said about the GTK callbacks two sections up.
The same mistake, made twice in one document, about two different instruments.

**The real trigger is [[feature-a-object-output-for-i386-arm32-and-aarch64]]**
(A, p70) — an i386 object linked by a gcc-built i386 caller. **It landed hours
later and fired; the measurement is the next section.** One thing does not
transfer from the x86-64 writer, per frankC: on i386 an external call also goes
through a `.data` GOT slot and needs the two-relocation treatment, whereas
`writeELF32Rel` relocates a `.text` literal directly against the extern. Porting
the ESP writer by adding `machine := 3` would produce an object that links and
jumps to zero.

The escaping-function-pointer hazard this ruling parked is now **live**: the
x86-64 export surface is `ProcCdecl`-only, so a direct export is cdecl by
construction, but `@proc` through an exported cdecl routine reaches it. frankC
flagged rather than silently owned it; it is in that ticket's trip-wire.
---

# TRIGGER FIRED 2026-08-31 — the measurement, frankC

The corrected trigger above — an i386 object linked by a gcc-built i386 caller
— landed the same day and fired immediately. Here is what it says. **This section is EVIDENCE, not a ruling** — the ruling is
the owner's, and the numbers below are what it should be made on.

## The experiment

Two objects, same compiler (`cc0ef3dc2b44`), same writer, same target, same
`gcc -m32 -no-pie` caller. They differ in exactly one thing: whether
`CProcUsesCAbi` is True for the routine being called.

- **`CProcUsesCAbi` FALSE** — a C translation unit compiled standalone, so
  `CProgramMode` is True and `CUnitOfPascalProgram` is False. This is the
  landed option B's behaviour.
- **`CProcUsesCAbi` TRUE** — Pascal `cdecl` routines, same signatures.

An x86-64 build of both is the control, since x86-64 never diverged.

## Result: option B is observably wrong at the boundary

`CProcUsesCAbi` **FALSE** (C unit), called from `gcc -m32`:

| call | expected | i386 | x86-64 control |
| --- | --- | --- | --- |
| `i_none()` | 7 | 7 | 7 |
| `i_ii(1,2)` | 12 | **21** | 12 |
| `i_d(2.5)` | 5 | 5 | 5 |
| `i_id(2,3.5)` | 5 | **1074528256** | 5 |
| `d_none()` | 1.5 | **-nan** | 1.5 |
| `d_d(2.5)` | 3.5 | **-nan** | 3.5 |
| `d_ii(3,4)` | 7 | **-nan** | 7 |

`21` is `2*10+1`: **the two integer arguments arrive reversed.** Every `double`
— argument or return — is wrong.

`CProcUsesCAbi` **TRUE** (Pascal `cdecl`), same target, same writer, same
caller:

| call | expected | i386 |
| --- | --- | --- |
| `p_ii(1,2)` | 12 | 12 |
| `p_d_none()` | 1.5 | 1.5 |
| `p_d_d(2.5)` | 3.5 | 3.5 |
| `p_i_id(2,3.5)` | 5 | 5 |

**All four right.** So the population that an external C caller gets wrong is
exactly the population where `CProcUsesCAbi` is False, and the boundary
behaviour option A would produce is exactly the one that works. On the evidence,
**A**.

## Three things this does NOT say, stated because each could be read into it

1. **It does not price the change.** This measures BEHAVIOUR AT A BOUNDARY, not
   the cost of flipping the clause. The ruling above says option A is "deleting
   the third line", one definition and nine read sites; **I did not re-verify
   that**, and the seven `ProcCdecl[procIdx] and (not CProgramMode)` call-site
   guards this document calls load-bearing are a *different* expression from
   `CProcUsesCAbi`. Whoever implements A must confirm the call sites move with
   the callee, or C→C calls inside a C unit break — which is the exact failure
   this document already warned about.
2. **It does not cover arm32 or aarch64.** Neither has an object writer, so
   neither is measurable yet. i386 is one of the three divergent targets, not
   all of them, and the aarch64 AAPCS trip-wire is a separate open question with
   its own repro requirement.
3. **It is not confounded by the EBX bug found alongside it.**
   [[bug-a-i386-clobbers-ebx-across-a-cdecl-exported-function]] makes a
   `printf`-using caller crash *after* a correct return, so the values above
   were read through exit codes where the crash intervened. The values and the
   crash are independent, and the crash is on the `CProcUsesCAbi` TRUE side —
   i.e. it does not flatter option A.

## Why this took one command and eight months of not knowing

Nothing here is subtle. `i_ii(1,2) = 21` is visible at a glance. It was
unobservable only because no caller existed outside pxx's own convention, and
the whole corpus is self-consistent under either answer — which is the property
this document identified as the reason to defer. **The object writer did not
answer the question; it built the instrument that could.** That is what the
umbrella was priced for.

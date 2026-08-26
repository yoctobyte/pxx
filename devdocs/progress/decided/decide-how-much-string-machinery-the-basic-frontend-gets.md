---
slug: decide-how-much-string-machinery-the-basic-frontend-gets
title: "DECIDE: does a BASIC program pull builtinheap (≈100 KB) so `s + t` works, or stay 600 bytes and refuse?"
track: U
prio: 35
type: decide
blocked-by: []
status: decided
owner: ""
created: 2026-08-24
summary: "String concat and comparison between BASIC variables need PXXStrConcat/PXXStrEq, whose bodies ship only in builtinheap, which a unit-free .bas never pulls — so `PRINT s + t` is a compiler-internal error. Every OTHER frontend solves this by pulling builtinheap unconditionally (a Pascal hello-world is 63 KB). BASIC's unit-free path is 559 bytes. The fork is size vs capability, and it is a product call, not a code one."
---

# The fork

`PRINT s + t`, with `s` and `t` BASIC string variables and no `USES` in the
file:

```
pascal26:3: error: compiler error: call to a runtime stub that was never
emitted (code offset 0 is the ELF entry point). A frontend driver is missing
its stub-emission call for the current flags/target.
```

Same for `IF s = t` on aarch64/arm32 (`compiler error: PXXStrEq not found`;
x86-64 and i386 have an inline path). Present on `pinned`. Tracked as
[[bug-a-basic-string-concat-in-a-unit-free-program-is-a-compiler-error]] — this
ticket is the decision that unblocks it.

# What the measurement says, and why it does not settle it

The emitted AnsiString "runtime" is a set of SHIMS: `AnsiStrConcatAddr` is nine
pushes around `EmitCallProc(FindProc('PXXStrConcat'))`. **Every shim's body is a
builtinheap procedure**, and BASIC pulls builtinheap through exactly one door —
`USES <unit>` during the parse.

There is no frozen-string path that avoids this. Measured: a Pascal program
doing `ShortString + ShortString` also pulls builtinheap, and comes out at
**63,760 bytes**. That is not an accident of that program —
`DetectPascalRuntimeNeeds` sets `needsAnsiRuntime :=
PasDefineExists('PXX_MANAGED_STRING')`, and `PasApplyDefaults` defines that
symbol unconditionally, so *every Pascal program pulls builtinheap*, always.

So BASIC's small unit-free binary is the anomaly, not the norm:

| program | size |
| --- | --- |
| `10 PRINT "hello"` (.bas, no USES) | **559 B** |
| `WriteLn('hello')` (.pas) | 63,760 B |
| `test_basic_comprehensive.bas` (has USES) | 103,935 B |

# The three options

**A — pull `builtinheap` unconditionally in the BASIC driver.** One line
(`ParseUsesUnitAmbient('builtinheap')`), exactly what Pascal, C and NilPy do.
`s + t` and `s = t` work everywhere. **Every** `.bas` binary becomes ~100 KB,
including `10 PRINT "hello"`, which is 559 B today. Simple, consistent, and
throws away a property that was only just gained
([[bug-a-a-unit-free-basic-program-calls-a-helper-it-never-emits]], 2026-08-24).

**B — keep the small path; make the refusal a real diagnostic.** BASIC is a
skeleton frontend. Say *"BASIC: string concatenation requires a `USES` of any
unit"* instead of `compiler error: ... driver is missing its stub-emission
call`, which reads as an internal fault and points the user at nothing. Cheap,
honest, and leaves a language gap open.

**C — pull it on demand, after the parse.** BASIC's parse builds an AST and
emits no user code; `PatchProgramEntryJump` already happens *after*
`ParseBBlock`. So the driver could: parse → walk the AST for a managed-string
operation → `ParseUsesUnitAmbient('builtinheap')` only if one is present →
*then* emit the shims (they are reached only by call, so their position is free,
they need only precede lowering) → lower. Exact rather than approximate: small
programs stay small, string programs work. It is a real restructure of the
driver and the only option that needs design.

# Recommendation

**C, and B as the fallback if C is judged too much machinery for a skeleton
frontend.** C is the only one that does not trade one of the two properties
away, the "emit the shims after the parse" move is sound (nothing falls through
into them), and the AST walk is small. A is one line and consistent with every
other frontend, which is a real argument — but paying 100 KB on every BASIC
binary to fix an operator most `.bas` files never use is the wrong trade for a
frontend whose whole point is being small.

# What NOT to do

Do not emit the shims unconditionally "to be safe". That is precisely how
[[bug-a-a-unit-free-basic-program-calls-a-helper-it-never-emits]] happened: the
shim was emitted, its builtinheap body was not, and the only thing hiding it was
that nothing resolved the driver's forward calls — so the call kept its
placeholder for the whole compile and silently did not happen.

# Whatever is chosen

It must cover `+`, `=` **and** `<>`, and the gate must include the cross targets:
x86-64 and i386 have an inline compare path, so a native-only run would call two
of the three fixed.

---

# DECIDED 2026-08-25 — **option A: the BASIC driver pulls `builtinheap` unconditionally**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Judgement call on the
pragmatic tiebreak**, with one principle pointing the same way — labelled as
such so it is cheap to revisit, because it does trade a real property away.

One line, `ParseUsesUnitAmbient('builtinheap')`, exactly what Pascal, C and
NilPy already do. `s + t`, `s = t` and `s <> t` work on every target. Every
`.bas` binary becomes ~100 KB, `10 PRINT "hello"` included.

## The principle that points here

`normalise-dont-special-case.md`: *"When the frontend can reach a construct
through two shapes ... Normalise the special shape into the general one ... it
is a way of having **one** thing to get right instead of two that must stay in
step."*

Four frontends pull the runtime unconditionally; one does not. BASIC's unit-free
path **is** the special case, and it is already the one that is broken — the
ticket exists because a helper was called that was never emitted. Option C would
keep the special case and add a second mechanism (a conditional, post-parse
runtime pull) that no other frontend has, in Track A's shared driver ground.

## Why the pragmatic tiebreak decides the rest

The owner's standing framing is *a pragmatic **C + Pascal + Python** compiler —
a tool that compiles and correctly runs real programs.* Measured: BASIC has no
track letter, is named nowhere in `CLAUDE.md`, has five tests, and is described
in this ticket as *"a skeleton frontend."* Option C is *"a real restructure of
the driver and the only option that needs design"* — design effort in shared
core files, spent on a frontend outside the stated goal, to preserve a binary
size that no program depends on and that was gained **one day** before this
ticket was filed.

Against that, A costs one line and turns a compiler-internal error into working
string support. Tickets-closed-per-change, per `root-cause-over-microfix.md`,
strongly favours A.

## What is genuinely lost, stated plainly

The 559-byte unit-free binary. That is a real and attractive property and this
decision throws it away. Two things make it acceptable:

**It is not BASIC's problem.** A Pascal `WriteLn('hello')` is 63,760 bytes for
the same reason — `PasApplyDefaults` defines `PXX_MANAGED_STRING`
unconditionally, so *every* Pascal program pulls builtinheap. The size question
is global, and its correct answer is reachability-gated emission, not a
per-frontend hand-rolled pull. [[feature-emission-size-dce]] is that answer and
is marked done while a hello-world still weighs 63 KB, which is itself worth a
look.

**Fixing it generally recovers BASIC's small binary for free**, and fixing it
in BASIC only recovers it for the one frontend nobody ships from.

## Option B was rejected, but half of it is kept

B's diagnostic reasoning is right about the *message* and wrong about the
outcome: shipping a good error for a feature we can enable in one line is
choosing to keep a language gap. But the underlying complaint stands — the
current text (*"compiler error: ... driver is missing its stub-emission call"*)
reads as an internal fault and points the user at nothing. Any BASIC construct
that still cannot be lowered after this should say so in BASIC's terms.

## Heeding the ticket's own warning

Do **not** emit the shims unconditionally without their bodies. That is the
exact mechanism of
[[bug-a-a-unit-free-basic-program-calls-a-helper-it-never-emits]] — the shim
emitted, the builtinheap body not, and nothing resolving the driver's forward
calls, so the call kept its placeholder for the whole compile and silently did
not happen. Pulling the unit is what makes the bodies exist; that is the point
of A over "emit the shims to be safe."

## Re-filed as work

- Track **A**: [[bug-a-basic-string-concat-in-a-unit-free-program-is-a-compiler-error]]
  is unblocked and carries the one-line fix. Prio 35. **Gate must include the
  cross targets** — x86-64 and i386 have an inline compare path, so a
  native-only run would exercise two of the three fixed shapes.
- Track **A/O**: `bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce`,
  prio 30 — the general size question this decision defers to. If it lands, the
  559-byte BASIC binary comes back on its own.

## Log
- 2026-08-25 — decided, commit 28c19f214.

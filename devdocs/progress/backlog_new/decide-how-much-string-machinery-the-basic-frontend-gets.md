---
slug: decide-how-much-string-machinery-the-basic-frontend-gets
title: "DECIDE: does a BASIC program pull builtinheap (≈100 KB) so `s + t` works, or stay 600 bytes and refuse?"
track: U
prio: 35
type: decide
blocked-by: []
status: backlog_new
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

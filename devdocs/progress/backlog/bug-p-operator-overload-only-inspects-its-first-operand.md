---
summary: "`operator + (a: Double; b: TCx): TCx` is refused at the DECLARATION — 'cannot determine operand type'; the Integer form is refused as 'predefined for built-in operand types'. FPC accepts both. One cause: the declaration inspects only its FIRST operand, for the type name and for the is-this-legal test alike."
type: bug
prio: 45
track: P
blocked-by: []
---

# An operator overload only ever inspects its first operand

- **Type:** bug (Pascal frontend, FPC compat) — Track P, in the shared
  `compiler/parser.inc`, so it runs under Track A's gate.
- **Found:** 2026-08-16, while implementing
  [[bug-nilpy-no-complex-number-type]] — reflected arithmetic (`1 + z`) needs
  exactly the shape that is refused. Filed separately because it is a Pascal
  frontend bug in its own right and is not about complex numbers at all.

## Measured, against `fpc -O- -Mobjfpc`

```pascal
type TCx = class re, im: Double; end;

operator + (a, b: TCx): TCx;         { pxx: ok        FPC: ok }
operator + (a: TCx; b: Double): TCx; { pxx: ok        FPC: ok }
operator + (a: Double; b: TCx): TCx; { pxx: REFUSED   FPC: ok }
operator + (a: Integer; b: TCx): TCx;{ pxx: REFUSED   FPC: ok }
```

Two different diagnostics, one cause:

| declaration | pxx says |
| --- | --- |
| `(a: Double; b: TCx)` | `operator: cannot determine operand type` |
| `(a: Integer; b: TCx)` | `impossible operator overload: this operation is predefined for built-in operand types` |

FPC compiles and runs both; a program using `1.5 + MkCx(1,2)` prints `2.5`
under FPC and does not build under pxx.

Note the first three rows: a mixed `(TCx, Double)` overload **is** accepted
alongside the `(TCx, TCx)` one, so this is not the "one overload per operator
per type" limitation that `lib/rtl/ucomplex.pas:5-17` records. It is
specifically the operand ORDER — a built-in type on the LEFT.

## Cause — the declaration reads half of its own signature

`parser.inc:2566-2591` scans ahead for the **first `:` inside the parens** and
takes that one type as *the* operand type:

```pascal
{ Lookahead: find first ':' inside '()' to get operand type name }
...
if typeName = '' then Error('operator: cannot determine operand type');
```

That single value then drives both the registration key (`opTypeKind` / `recId`,
`parser.inc:2600-2633`) and the legality test at `parser.inc:2738-2741`:

```pascal
{ FPC forbids overloading a BINARY symbol operator when the operation is
  predefined for the operand types -- at least one operand must be a
  record/class ... }
if recId = REC_NONE then
  Error('impossible operator overload: this operation is predefined for built-in operand types');
```

**The comment states the rule correctly and the code implements a different
one.** "At least one operand must be a record/class" is a test over BOTH
operands; `recId` describes only the first. So a legal `(Integer, TCx)` is
rejected as though both sides were built-in.

The `Double` row fails one step earlier and for a second reason: the lookahead
maps only four builtin type TOKENS back to names (`tkInteger_T`, `tkBoolean_T`,
`tkChar_T`, `tkString_T` — `parser.inc:2581-2586`). `Double`, `Real`, `Single`,
`Int64`, `Byte`… lex as their own tokens, match none of them, and leave
`typeName` empty. Curiously the *scalar* resolution below (`parser.inc:2612-2627`)
already handles `'double'`/`'real'`/`'extended'`/`'single'` **by name** — so the
support is there and only the token→name step is missing.

## Fix shape — read the signature, do not re-derive it

The lookahead exists to compute `opTypeKind`/`recId` **before** `ParseSubroutine`
runs, but neither value is actually USED before it: they are consumed by the
checks and the registration afterwards (`parser.inc:2715+`). After
`ParseSubroutine` the real signature is available — `Procs[procIdx].Params[0..1]`
with `ProcParamRecId` beside them — with no token scanning, no token→name table,
and no first-operand assumption.

So the microfix is to extend the token→name list and test both operands; the
overhaul is to **delete the lookahead** and key the checks and the registration
off the parsed parameters. The overhaul deletes a table rather than growing one
and removes the class of bug entirely, which is what
`devdocs/dev/root-cause-over-microfix.md` asks for.

The one thing to settle first is the REGISTRATION key: `FindOpOverload2(op,
leftTk, leftRec, rightTk, rightRec)` is the lookup, and it must keep matching
whatever the registration writes. Registering under the first operand is
presumably why the lookup ever worked; a both-operand key has to be checked
against every existing use, including the `:=`/`Implicit`/`Explicit` single-param
forms whose "operand" is param 0.

## Gate

The four-row table above as a test, its `.expected` captured from FPC, plus the
existing `test/test_op_overload.pas` and `lib_ucomplex.pas` staying green;
`make compiler/pascal26` (self-host fixedpoint); `tools/gate.sh quick`.

## The use site is left-keyed too — this is bigger than the declaration

Fixing the declaration alone would not make `1.5 + z` work. The registry
(`symtab.inc:4766-4773`) keys every entry on the LEFT operand, and the call site
only consults it when the LEFT operand is a record/class:

```pascal
if (IntToTypeKind(ASTTk[left]) = tyRecord) or (IntToTypeKind(ASTTk[left]) = tyClass) then
  opci := FindOpOverload2(...);        { parser.inc:17199-17201 }
```

So a `(Double, TCx)` overload would register under `tyDouble`/`REC_NONE` and
never be looked up. `FindOpOverload2`'s own header comment already records that
the left-only key was a known compromise ("Rather than widen the table,
disambiguate here"); a built-in left operand is the case that compromise cannot
cover, because there is nothing to disambiguate from.

Whole job, then: (1) read the real signature instead of the first-`:` lookahead,
(2) accept when EITHER operand is a record/class, (3) let the use site consult
overloads when the RIGHT operand is one. (3) is the part that needs care — it
adds a lookup to a hot path that today exits immediately on a scalar left
operand.

**Not a blocker for [[bug-nilpy-no-complex-number-type]].** Python's reflected
arithmetic is `__radd__`, a frontend concept, not a Pascal operator: NilPy has
to grow that arm for complex regardless of what the Pascal operator machinery
does. The two overlap only in that both were reached from `1 + z`.

---
slug: feature-p-fpc-global-operator-overload-declarations
track: P
prio: 72
type: feature
blocked-by: []
summary: "`operator := (const u:qword):Tconstexprint;` — FPC's UNIT-SCOPE operator overload declaration — is not parsed. It is the first wall behind the FPC-compiler define profile: constexp.pas:58, and constexp is what cutils and cstreams pull in first."
status: done
---

# FPC global (unit-scope) `operator` overload declarations

Found 2026-08-21 immediately behind
[[feature-mimic-fpc-compiler-define-profile]], which cleared
`{$i fpcdefs.inc}`. This is the next wall on the `cutils` / `cstreams` path.

## Repro

```pascal
{ FPC 3.2.2 compiler/constexp.pas, lines 58-62 }
operator := (const u:qword):Tconstexprint;inline;
operator := (const s:int64):Tconstexprint;inline;
operator := (const c:Tconstexprint):qword;
operator := (const c:Tconstexprint):int64;
operator := (const c:Tconstexprint):bestreal;
```

```
$ pascal26 --mimic-fpc-compiler p_cutils.pas
Expected: =, but got:  (Kind: 75, Line: 360)
pascal26:360: error: unexpected token
  near:   const u  qword >>>   Tconstexprint
```

(The line number is wrong — the token is `constexp.pas:58`. That is a separate
finding, [[bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file]].)

## What it is

FPC's `{$mode objfpc}` operator overloading at **unit scope**, not inside a
class: `operator <op> (params) : result;` with an implementation later in the
unit. `:=` is the implicit-conversion operator, which is how `Tconstexprint`
(FPC's compiler-wide "constant expression integer" record, holding either an
int64 or a qword plus an overflow flag) is assignable from and to plain
integers throughout the FPC compiler.

pxx already knows the CONCEPT — `--strict-operator` exists and the dialect has
operator overloading — so the gap is likely the unit-scope declaration form and
the `:=` operator name rather than overloading itself. Confirm before scoping.

## Why it matters beyond FPC

`operator :=` implicit conversion is how a Pascal library gives a record value
semantics against builtin types. Any real FPC corpus that wraps a scalar in a
record for range/overflow tracking hits this, so it is not FPC-compiler-specific
surface.

## Gate

`constexp.pas` parses; `cutils.pas` and `cstreams.pas` get past it under
`--mimic-fpc-compiler`. Plus the Pascal suite green and self-host
byte-identical. Cross-target breadth is Track T's.

## Outcome — 2026-08-27

The ticket's premise had gone stale and the ticket said what to do about that:
*"pxx already knows the CONCEPT … so the gap is likely the unit-scope
declaration form and the `:=` operator name rather than overloading itself.
Confirm before scoping."* Confirmed, and it was neither. Measured, unit-scope
`operator :=` and unit-scope binary operators with grouped params
(`(const a,b:T)`) already parsed. **Three different gaps** stood behind the one
error message, and all three are visible in `constexp.pas`, which declares 22
operators on one record:

1. **A UNARY overload was refused outright.** `operator - (const a:T):T;` fell
   into the binary arm and died on *"binary operator must take exactly two
   parameters"* — the ticket's second error, at `constexp.pas:298`. Note the
   diagnostic pointed at the *next* declaration, which is why this read as a
   `*` problem and not a `-` one; `operator - (const a:T):T` **alone** in a
   three-line program reproduces it.
2. **The keyword-spelled operators were not accepted at all.** `and`, `or`,
   `xor`, `shl`, `shr` and `not` were missing from the symbol list, so
   `operator and (const a,b:T):T` was a syntax error while
   `operator + (const a,b:T):T` was fine — a distinction Pascal does not draw.
   `constexp.pas:78-82` declares five of them.
3. **An `AN_NEG` / `AN_NOT` node had no record identity.** `ResolveNodeRec` had
   an `AN_BINOP` arm and no unary twin, so `(-a) + b` could not find the `+`
   overload (*"no operator overload found for record operands"*) and an
   inferred `var c := -a` would have been sized `REC_NONE`.

### What landed

- `FindOpOverloadUnary` (`symtab.inc`) — same table, same
  `(opKind, leftKind, leftRec)` key, **arity as the discriminator**. One symbol
  legitimately carries both arities; `constexp.pas:65,66` is exactly that pair.
- `FindOpOverload2`'s aggregate fallback now requires `ParamCount = 2`. Without
  that, `a - b` would have been handed the one-parameter proc through
  `firstHit` — the failure a partial version of this fix would have shipped
  silently, since the fallback answers *before* any arity is checked.
- The arity branch in `pasparser_call.inc` accepts a one-parameter `-` / `not`,
  with the same "operand must be an aggregate" rule the binary branch uses.
- `and/or/xor/shl/shr/not` added to the accepted-symbol list.
- `AN_NEG` / `AN_NOT` arms in `ResolveNodeRec`, in `ParseFactor` (result tag),
  and in `ir.inc` (the call), mirroring the binary path at each.

### Two things found while there, both flagged rather than folded in

- **`shr` has no token.** `shl` lexes as `tkShl` (`lexer.inc:327`); Pascal `shr`
  lexes as a plain `tkIdent` whose text is `'shr'`, which is why `ParseTerm`
  spells the pair `(Kind in [… tkShl]) or ((Kind = tkIdent) and (SVal =
  'shr'))` at **three** sites. So `operator shr`'s table key has to be
  `Ord(tkIdent)` — that is what the use site stores in `ASTIVal`. One concept,
  two lexings; unifying it is a lexer change with three parser sites behind it,
  so it is documented at the new call site and left alone.
- **Unary `+` is deliberately absent.** `ParseSimpleExpr` eats a leading plus as
  an identity before any node exists, so there is nothing to dispatch on and
  supporting it means a second mechanism somewhere else. No corpus needs it.

### Gate — the ticket's own, and where it now stops

`constexp.pas` gets through **every one of its 22 operator declarations and
implementations**, and `cutils.pas`, `cstreams.pas` and `cclasses.pas` all now
reach the same single wall, which is inside a constexp function BODY and is
already filed:

```
pascal26:321: error: undefined variable (qword)
  in: <fpc-source>/compiler/constexp.pas
  near:  and  high  qword >>>  div bb
```

`constexp.pas:321` is `if (bb<>0) and (high(qword) div bb<aa) then`.
`OrdinalTypeBound` refuses the unsigned 64-bit names on purpose and says so:
*"their High is 2^64-1, which this evaluator's Int64 cannot carry, and
answering -1 would turn a refusal into a wrong value."* That is
[[feature-p-const-evaluator-carries-unsigned-64-bit]], already in backlog — so
the wall this ticket was opened on is gone and the next one needs no new
ticket.

Worth noting, since this ticket complained about it twice: the diagnostic above
names the **right file and the right line**. The wrong-line finding
([[bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file]]) does not
reproduce on this path any more.

One thing behind the wall is NOT yet filed and will surface once it clears:
`operator :=` is looked up on an **exact type-kind match**, so with
`operator := (const s:int64):Tconstexprint` declared, `c := 10` fails
(*"cannot assign Integer to record"*) where FPC accepts it. Filed as
[[bug-p-an-implicit-conversion-operator-needs-an-exact-type-kind-match]].

### Measured

`test/test_operator_unary_and_keyword_forms.pas` (+ `.expected`, wired into
`test-core`) — 14 rows, byte-identical to `fpc -O- -Mobjfpc` 3.2.2: the shared
`-` symbol at both arities, a unary result feeding a binary operator
(`(-a) + b`, `-(a - b)`, `-(-a)`), all five binary keyword operators, unary
`not` and `not (not a)`, and a unary result compared through an overloaded `=`.

### Gate

`make compiler/pascal26` byte-identical (aec53b7b8235) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0 · fgl 7/7.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.

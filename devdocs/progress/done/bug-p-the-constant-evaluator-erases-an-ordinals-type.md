---
summary: "the const evaluator represents every ordinal as a bare Int64, so `const X = eB` prints 1 instead of eB and `const C = Low(TC)` prints 97 instead of 'a'"
type: bug
track: P
prio: 42
status: done
owner: opus5-frank1
---

# The constant evaluator erases an ordinal's type

Found 2026-08-26 by measurement, while fixing
[[bug-p-every-compile-time-intrinsic-hand-rolls-its-own-operand-parser]]'s
index-type row. It is NOT that fix: the array Low/High folds now carry the
index type correctly through the EXPRESSION path, and this is the const path,
which never had a type to carry.

## The measurement

`fpc -Mobjfpc -O1` 3.2.2 vs pxx at `902e53050`.

```pascal
type TE = (eA, eB, eC);
     TC = array['a'..'e'] of Integer;
const
  X = eB;
  Y = 'q';
  Z = Low(TE);
  W = Low(TC);
```

| expression | fpc | pxx |
| --- | --- | --- |
| `WriteLn(X)` | `eB` | **1** |
| `WriteLn(Y)` | `q` | `q` |
| `WriteLn(Z)` | `eA` | **0** |
| `WriteLn(W)` | `a` | **97** |

Note `Y` is right, which is what makes this look narrower than it is: the char
arm of `ParseConstSection` calls `AddConst(name, tyChar, ...)` at that ONE site,
so a char LITERAL survives while everything that reaches the same place through
`ConstEval` does not.

## Root cause

`ConstEval` returns an `Int64` and nothing else. Its own comment states the
design outright:

> This evaluator already represents every ordinal value (char, enum, bool) as a
> bare Int64 — a char literal folds to its own ordinal via the tkString branch
> above, an enum member via the TEnum.member branch — so Ord(x) needs no
> conversion at all: it IS whatever x already evaluates to here.

That is a genuine simplification for arithmetic and it is why `Ord`/`Succ`/`Pred`
need no code at all. The cost is that the caller declaring the constant has no
way to ask what kind of ordinal came back, so it guesses from the FIRST TOKEN
(`if CurTok.Kind = tkString then tyChar else tyInteger`) — which is right for a
bare literal and wrong for every folded form.

`TryConstHighLowValue` already knows the answer and throws it away: its
expression twin `TryFoldHighLowType` stamps `ASTTk`/`ASTEnumId` on the node it
builds, and `TryArrayTypeBound` now hands both of them back. The const caller
passes them to nothing.

## The fix

Give `ConstEval` a companion out-value the way `TryArrayTypeBound` just got one
— a `LastConstEvalTk`/`LastConstEvalEnumId` pair, or an overload that returns
the kind — and have `AddConst` take it instead of re-deriving the kind from
`CurTok.Kind`. The producers already exist:

- `TryConstHighLowValue` — the array/enum/ordinal bounds (this is the row that
  found the bug);
- the `TEnum.member` branch — knows its `FindEnumType` result;
- the `tkString` char-literal branch — already special-cased at the AddConst
  site, and would stop being special.

The `Ord(x)` branch must deliberately reset the kind to Integer: `Ord` is
exactly the operator that discards the type, and inheriting its operand's kind
would make `const N = Ord('a')` print `a`.

## Why prio 42 and not higher

Real, silent, and wrong output rather than a compile error — but the shapes that
hit it are `const` declarations of enum and char values used directly in
`WriteLn`, which is narrower than it sounds because the same constants used as
array indices, case labels or in arithmetic are all correct today. Above the
formatting/diagnostic tier, below the ones that miscompile.

## Gate

The four rows above matching `fpc -O1`, `const N = Ord('a')` still printing 97,
the two `const CLO = Low(TC)` rows currently held out of
`test/test_low_high_index_type.pas` restored to it, and self-host byte-identical.

## Outcome

Fixed by generalising the channel that already existed rather than adding one
beside it. `CEIsBool: Boolean` becomes `CEOrdTk: TTypeKind` + `CEEnumId:
Integer`, and every site that set or read the boolean now sets or reads the
kind. There is no `CEIsBool` left in the tree — the boolean case is
`CEOrdTk = tyBoolean`, which is what keeps this one mechanism instead of two.

An enum is not a `TTypeKind` in this dialect: an enum symbol is `tyInteger`
carrying `SymEnumId`, the shape `ParseVarDecl` already produces for `var e: TE`.
So the kind alone could not carry it and `CEEnumId` is the companion. The
declaration site stamps `SymEnumId` on the sym `AddConst` returns, and `WriteLn`
resolves the member name from there with no further work.

Producers, all of which already knew the answer:

- `TryConstHighLowValue` — every arm. Its expression twin `TryFoldHighLowType`
  stamps `ASTTk`/`ASTEnumId` on the node it builds; this one had the same facts
  and discarded them, including the `tabIdxTk`/`tabIdxEnumId` pair
  `TryArrayTypeBound` hands back, under a comment saying a const context has
  nowhere to put a type — true only because the channel did not exist yet.
- the `TEnum.member` branch — `FindEnumType` off the name it is standing on.
- the char-literal branch — `tyChar`.
- `Chr` — `tyChar`, the operator that ADDS the type.
- a named ordinal const — its own `TypeKind` and `SymEnumId`.

`Ord` deliberately RESETS the channel; it is exactly the operator that discards
the type, and inheriting the operand's would make `const N = Ord('a')` print
`a`. `Succ`/`Pred` keep it, which is what makes `const E = Succ(eA)` print `eB`
for free. Arithmetic and the integer typecast clear it, exactly as the boolean
rule already did.

The one-character-LITERAL arm of `ParseConstSection` is untouched: it sits on
the string-token path, not the ConstEval path, and was already right.

## Gate, as specified

All four measured rows now match `fpc -Mobjfpc -O1`, and 29 more with them:
`test/test_const_eval_ordinal_type.pas` (+ `.expected`), pinned against FPC
3.2.2 — the Ord rows included, as the guard on the other side. The two
`const CLO = Low(TC)` rows held out of `test/test_low_high_index_type.pas` are
restored to it, with two enum-index rows beside them, and its `.expected`
regenerated from FPC.

Self-host byte-identical (fixedpoint converged in 1 round). Corpora:
pascal-conformance 346/0/170/34, fgl 7/7, c-conformance 220/0 — all unchanged.
`gate.sh quick` GREEN.


## Log
- 2026-08-26 — resolved, commit 3f63772de.

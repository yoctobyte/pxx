---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`operator := (const s: Int64): TCe` is found only when the source expression's type kind is EXACTLY tyInt64, so `c := 10` fails with `cannot assign Integer to record` while `c := someInt64` works. FPC applies the conversion to any assignment-compatible source. Found behind feature-p-fpc-global-operator-overload-declarations; it is the wall after the High(QWord) one in FPC's constexp.pas."
status: done
owner: opus5-frank1
---

# An implicit-conversion operator is looked up on an exact type-kind match

- **Type:** bug (a refusal, not a wrong value) — Track P
- **Opened:** 2026-08-27, found while clearing
  [[feature-p-fpc-global-operator-overload-declarations]]

## Measured

```pascal
program w;
type TCe = record v: Int64; end;
operator := (const u: Int64): TCe;
begin Result.v := u; end;
var x: TCe; n: Int64;
begin x := 10; n := 7; x := n; end.
```

| declared source type | `x := 10` (a tyInteger literal) | `x := n` (a tyInt64 var) |
| --- | --- | --- |
| `Integer` | ok | **error: cannot assign Int64 to record** |
| `Int64`   | **error: cannot assign Integer to record** | ok |
| `QWord`   | **error: cannot assign Integer to record** | error |

FPC accepts every cell: the conversion operator applies to any source that is
assignment-compatible with the parameter type.

## Where it is

`FindOpOverload(Ord(tkAssign), typeKind, recId)` (`symtab.inc`) matches
`OvrlTypeKind[i] = typeKind` exactly, and the guard in `ir.inc:126` that lets
the assignment past the type check asks the same question. Neither widens
within the integer family, so the entry registered under `tyInt64` is invisible
to a `tyInteger` expression.

## Why it is not a one-line widening

The table is keyed on the SOURCE type and carries no destination, so "retry
over the integer family" can find an operator whose result is a completely
different record. With two conversion operators in scope —
`operator := (const a: Int64): TA` and `operator := (const b: Integer): TB` —
a widened lookup for `someTA := 10` could answer with TB's. FPC resolves this
by picking the best assignment-compatible match **for the destination type**,
which is information this lookup does not currently have.

So the fix is either (a) key the conversion entries on the destination record
as well and match source by assignment-compatibility, or (b) keep the exact
lookup and add a widening retry only when it is unambiguous. (a) is the one
that matches what FPC actually does; (b) is smaller and would leave a
second-order gap. State the choice in the ticket before writing code.

## Why it matters

`operator :=` is how a Pascal library gives a record value semantics against
builtin types, and an integer LITERAL is the commonest thing anyone assigns to
one — so the exact-match rule fails on the first line most users write. FPC's
own `constexp.pas` declares the pair `(const u:qword)` / `(const s:int64)` and
then assigns plain integer constants throughout, which is the corpus case.

## Gate

The table above, all cells, oracled against `fpc -Mobjfpc` 3.2.2. Plus the
Pascal suite green and self-host byte-identical. The corpus gate is
`constexp.pas` compiling once
[[feature-p-const-evaluator-carries-unsigned-64-bit]] clears the `High(QWord)`
wall ahead of it.

## Outcome — 2026-08-27

**Option (a)**, as the ticket asked to be stated before code: key the conversion
entries on the destination and match the source by assignment-compatibility.
(b) — "exact lookup plus an unambiguous widening retry" — was rejected because
the second-order gap it leaves is the *corpus* case: constexp.pas declares two
conversions to one destination, so a widening retry that fires only when there
is a single candidate would never fire there.

(a) turned out to cost **no new column**. The ticket's worry was that "the table
carries no destination"; it does — the destination is the operator proc's own
`RetType` and `ProcRetRecId`, which the lowering site was already reading three
lines later to validate its own answer.

### What landed

`FindOpConvRanked(opKey, srcTk, srcRec, dstTk, dstRec, maxRank)` in `symtab.inc`:
filter by destination first, then take the best-ranked source among what is
left. Three callers, one mechanism:

| caller | destination | maxRank |
| --- | --- | --- |
| `ir.inc` AN_ASSIGN rewrite | the LHS's kind + rec id | `OPCONV_RANK_MAX` |
| `AssignHasConversionOperator` | `tyUnknown` = wildcard | `OPCONV_RANK_MAX` |
| the declaration-time duplicate check | the new operator's own result | **0** |

The wildcard matters: `AssignHasConversionOperator` runs a pass EARLIER and is
only deciding whether to refuse a store. It was refusing `c := 10` before the
rewrite that would have handled it ever ran, so widening one without the other
fixes nothing.

`maxRank = 0` matters for the opposite reason. The duplicate check must stay
exact, or `operator :=(QWord): TCe` beside `operator :=(Int64): TCe` — the pair
constexp.pas actually declares — would be refused as one operator written twice.

### Two things the measurement changed

- **The rank order is FPC's, not invented.** Measured against `fpc 3.2.2
  -Mobjfpc` on constexp.pas's own pair: a literal and a signed `Integer` pick
  the `Int64` operator, a `Byte` picks the `QWord` one. So the rule is *exact
  kind, else same SIGNEDNESS, else any integer, else (last) a float parameter* —
  a Byte prefers the unsigned parameter even though the signed one would hold it.
  A float source reaches only a float parameter; FPC has no implicit
  float-to-integer and neither has this.
- **The duplicate check was over-strict and had to move with the lookup.** It
  read "a second conversion from the same source to a result of the same type
  KIND", which made `operator :=(Integer): TA` and `operator :=(Integer): TB` a
  duplicate — both are `tyRecord`. FPC takes that pair. It now asks the same
  `OpConvResultMatches` the lookup does, so "the same result type" is decided in
  ONE place: same kind, frozen strings equivalent, and for a record/class the
  same rec id. `String[80]` vs `String[90]` (toperator92/95) stays a duplicate,
  because both are frozen-string kinds with `REC_NONE` — which is exactly why
  that rule was written.

`TkIsIntegerFamily` is deliberately narrower than the existing `TypeIsOrdinal`,
which also answers True for Boolean, Char, Pointer and the C/UTF ordinals.
Routing a Char through an `operator :=(u: Integer)` would be a wrong answer
rather than a missing one.

### Measured

Acceptance matrix, five declared parameter types × six sources, now identical to
FPC's (it was the diagonal):

| param \ source | `10` | Integer | Int64 | QWord | Double | Byte |
| --- | --- | --- | --- | --- | --- | --- |
| `Integer` | ok | ok | **ok** | **ok** | — | **ok** |
| `Int64`   | **ok** | **ok** | ok | **ok** | — | **ok** |
| `QWord`   | **ok** | **ok** | **ok** | ok | — | **ok** |
| `Double`  | **ok** | **ok** | **ok** | **ok** | ok | **ok** |
| `Byte`    | **ok** | **ok** | **ok** | **ok** | — | ok |

(bold = newly accepted; the `Double`-source column is refused for integer
parameters, matching FPC.)

`test/test_implicit_conversion_operator_widens_source.pas` (+ `.expected`, wired
into `test-core`) carries that matrix, the float rows, the two-destination
ambiguity guard (`TA`/`TB` from one `Integer` source) and constexp.pas's
one-destination pair with its five resolutions. Byte-identical to `fpc -O1
-Mobjfpc` 3.2.2. Both duplicate rejections re-verified by hand.

### Gate

`make compiler/pascal26` byte-identical (7a7a84514b53) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0 · fgl 7/7. The
corpus gate named in the ticket — `constexp.pas` compiling — cleared earlier
today under `--mimic-fpc-compiler`.

## Log
- 2026-08-27 — resolved, commit b67170d9d.

---
track: P
prio: 35
type: bug
blocked-by: []
summary: "pxx refuses `operator <op> (a, b: T)` unless one operand is a record or class. FPC's actual rule is narrower — it refuses only when the operation is ALREADY DEFINED for those operand types — and the gap is 91 of 209 measured same-type cells: `operator div (a, b: Single)`, `operator and (a, b: Char)`, `operator >< (a, b: LongInt)`, `operator - (a, b: AnsiString)` are all legal FPC and all refused here. The measured table is in tools/operator_predefined_matrix_probe.py, which compiles every cell with both compilers; the fpc column IS the specification. Two halves and only the first is a small change: the declaration CHECK, and then making a scalar-keyed overload actually FIRE at the use site, which today consults the table only when an operand is an aggregate. The two halves make each other safe — with a correct check, a registered scalar entry can only exist for a pair with no predefined meaning, so consulting the table unconditionally cannot shadow builtin arithmetic. Blocks toperator78."
status: backlog
owner: unassigned
---

# The operator "already predefined" check is an aggregate approximation

- **Found:** 2026-09-06 (frankS), adding Pascal `**`
  ([[feature-pascal-corpus-fpc-testsuite]], toperator78).
- **Measured** at compiler `5990846139a2` against fpc 3.2.2, 209 cells, by
  `tools/operator_predefined_matrix_probe.py`.

pasparser_call.inc says it plainly and the comment is honest about being an
approximation: *"FPC forbids overloading a BINARY symbol operator when the
operation is predefined for the operand types — at least one operand must be a
record/class"*. The second clause is not the first one.

## The measured table — this is the whole specification

fpc REFUSES exactly these same-type pairs, and accepts every other cell:

| op | operand type (both operands) |
| --- | --- |
| `+` | LongInt AnsiString ShortString Char Single Double TSet TEnum |
| `-` | LongInt Single Double **Pointer** TSet TEnum |
| `*` | LongInt Single Double TSet |
| `/` | LongInt Single Double |
| `div` `mod` `shl` `shr` | LongInt |
| `and` `or` `xor` | LongInt Boolean |
| `=` `<>` `<` `<=` `>` `>=` | LongInt AnsiString ShortString Char Single Double Boolean Pointer TSet TEnum |
| `><` | TSet |
| `**` | *(nothing)* |

The two asymmetries are the ones a hand-written table would have got wrong, so
they are why this was measured: **`+` on Pointer is NOT predefined and `-` on
Pointer IS** (pointer difference exists, pointer sum does not), and **`+` on
Boolean is not predefined while `and`/`or`/`xor` on Boolean are**.

pxx accepts 26 of the 209: the 19 `TRec` rows, plus 7 `**` rows exempted when
`**` landed. **That exemption is a special case this ticket deletes** — `**` is
simply a row of the table with nothing in it, and once the check asks the table
it needs no arm of its own.

## Two halves, and the second is the real work

1. **The declaration check** — replace the aggregate test with
   `OperationIsPredefined(opKey, leftTk, rightTk)` built from the table above,
   generalised to MIXED pairs by type family (numeric / stringy / set / enum /
   pointer / boolean). Small, and the probe re-run is its own regression test.
2. **The use site** — a scalar-keyed overload must FIRE. Today
   `ParseSimpleExpr`/`ParseTerm` consult the table only when
   `TkIsRecordOrClass` holds for an operand, so accepting the declaration
   without this leaves a **silently inert operator**, which is worse than the
   refusal it replaces.

**The halves make each other safe, and that is the design rather than a
coincidence.** The comment in pasparser_call.inc warns that widening the check
alone would be worse than the refusal, because a scalar entry lands under
`(tkStar, tyInteger)` and plain `3 * 5` would find it. With half 1 correct that
cannot happen: a registered scalar entry can only exist for a pair the table
says has no predefined meaning, so "predefined → builtin, otherwise → table" is
a partition and not a race. Do not land half 2 without half 1.

## A THIRD half, found after the ticket was written, and it is the one that
## actually gates toperator78

`OperandTypeKindRec` (pasparser_call.inc:26) resolves an operand type name from
exactly three places: `IsRecordType`, `FindUClass`, and `BuiltinTypeNameTk`
(plus `string`/`ansistring` by hand). **A user-declared non-record type has no
path at all** — measured at `b0e691210256`, all three of these are
`operator overloading: <name> is not a supported operand type`:

```
operator ** (left, right: ShortString) ...
operator ** (left, right: TSet)   ...   TSet  = set of TEnum
operator ** (left, right: TEnum)  ...   TEnum = (eA, eB, eC)
```

So the 209-cell matrix above UNDERSTATES the gap in one direction and overstates
it in another: three of its type columns never reach the predefined check at all,
and relaxing that check alone would not accept them. toperator78 declares
`operator and (left, right: TTests)` over a set and two `array of Char`
operands, so it needs this half as well as the other two.

**tforin15 fails on this same message** (`Twice is not a supported operand
type`, `Twice = type Integer`) and is NOT fixed by widening it: resolving
`Twice` to tyInteger makes it collide with the `operator enumerator(Integer)`
declared beside it, which is that row's real subject — a distinct scalar type
has no identity in a table keyed on (typeKind, recId). One message, two rows,
two different causes underneath it.

## Not the same as toperator91/94

Those are the duplicate-CONVERSION check keying on the result type KIND
(String[80] vs String[90]). Different check, different site.

## A smaller thing found alongside, not fixed

The refusal is raised AFTER `ParseSubroutine`, so it reports the line the parser
has reached — the token after the operator's BODY — not the declaration. On
toperator78 that reads as `pascal26:14 ... near: operator + (left:` for a
refusal that is actually about the `operator ><` at line 9, and it cost a wrong
sentence in that row's skip reason before it was noticed. Every diagnostic in
that tail has the same offset.

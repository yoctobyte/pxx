---
track: P
prio: 35
type: bug
blocked-by: []
summary: "RESOLVED 2026-09-09: OperationIsPredefined carries the measured table and both halves landed together -- the declaration check asks it instead of 'is one operand an aggregate', and both use-site guards widened so a scalar-keyed overload actually fires. Re-measured with the ticket's own probe: the fpc specification column did not move, pxx went from 8 accepted non-TRec cells to 87 losing none, and the shadow check (pxx accepting what fpc calls predefined) is clean. `**` has no exemption any more -- it is a row with nothing in it. THE TICKET'S MIXED-PAIR PLAN DOES NOT SURVIVE MEASUREMENT and is corrected in the resolution: the mixed matrix is irregular, `+ (LongInt,Pointer)` is predefined while `- (LongInt,Pointer)` is not and `+ (Pointer,Pointer)` is not while `-` is, so mixed pairs answer conservatively True = today's behaviour. The probe caught one cell no behaviour row would have: Pascal `shr` is a tkIdent renamed to tkShrLogical, not tkShr, so `operator shr (a,b: LongInt)` was accepted while `shl` was refused. Counts corrected: fpc refuses 92 not 91 (the hand-copied table itself is exactly right, diffed cell by cell). ShortString now resolves as an operand type; TEnum and array operands do not, and the remaining 11 gap cells are all the TEnum column, split out as its own ticket."
status: done
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

## Resolved 2026-09-09 — the table replaced the approximation, both halves

`OperationIsPredefined(opKey, ltk, rtk)` in `symtab.inc` carries the measured
table. The declaration check asks it instead of "is one operand an aggregate",
and both use-site guards in `pasparser_expr.inc` now read
`TkIsRecordOrClass(...) or not OperationIsPredefined(...)`, so a scalar-keyed
overload can actually fire.

**Measured with the ticket's own probe, before and after.** The fpc column —
the specification — did not move. pxx went from accepting **8** non-TRec cells
to **87**, losing none, and the shadow check (does pxx accept a cell fpc calls
predefined?) is **clean**. Of the 117 cells fpc accepts, pxx now accepts 106.

`**` has no exemption any more. It is a row of the table with nothing in it,
which is what the ticket asked for.

### The probe caught a cell no test would have

`operator shr (a, b: LongInt)` was **accepted** while `shl` on the same pair was
refused. The lexer gives `shr` no token: it arrives as a `tkIdent` whose text is
`'shr'`, and the declaration and the use site both rename it to
**`tkShrLogical`** on the way in — `tkShr` is the ARITHMETIC shift, C's `>>` on
a signed operand. A table naming `Ord(tkShr)` misses Pascal's `shr` entirely.
Found by the shadow check, not by any behaviour row, which is the argument for
keeping the probe as the table's regression test.

### The ticket's half-1 plan does not survive measurement

> *generalised to MIXED pairs by type family (numeric / stringy / set / enum /
> pointer / boolean)*

**The mixed matrix is irregular and a family rule gets it wrong in both
directions.** Measured 2026-09-09, 96 mixed cells:

- `+ (LongInt, Pointer)` is predefined; `- (LongInt, Pointer)` is **not**
- `+ (Pointer, Pointer)` is **not** predefined; `- (Pointer, Pointer)` **is**
- `+ (Char, AnsiString)` is predefined; `+ (LongInt, Char)` is **not**
- `div` and `and` have **no** predefined mixed pair at all

So mixed-family pairs answer `True` — a deliberate conservatism, not the rule.
That is exactly today's behaviour (a mixed scalar pair is refused now), so this
change can only widen what is accepted and never narrow it. Closing the mixed
gap needs an 11×11×19 measurement nobody has taken; it is not a rule anyone can
guess at, and the sample above is why.

### Two counts corrected

- fpc refuses **92** of 209, not 91. The ticket's hand-copied table is
  otherwise **exactly right** — re-measured and diffed cell by cell, zero
  differences across all 19 operators. Only the prose count was off, so nobody
  should re-measure the table on account of it.
- pxx accepted **8** non-TRec cells before this change, not 7.

### Half 3 is half done, and the rest is now its own ticket

`ShortString` was a builtin string name with no door: `BuiltinTypeNameTk`
deliberately excludes it (it sets `LastTypeStrCap`, and that table holds only
side-effect-free names), so `operator + (a, b: ShortString)` answered
`ShortString is not a supported operand type` while `AnsiString` and `Char`
resolved. `OperandTypeKindRec` now asks `StringTypeNameKind` when the scalar
table abstains. `TSet` already resolved via the alias arm added 2026-09-07.

**`TEnum` and array operands still do not resolve, and the remaining 11 cells
of the gap are all the TEnum column** — every one of them fails at the
operand-NAME door, not at the predefined check. That is
[[bug-p-an-enum-or-array-type-cannot-be-named-as-an-operator-operand]].

**pxx has no `tyEnum`.** An enum operand carries an integer kind, so two cells
(`*` and `/` on an enum pair) will answer "predefined" where fpc accepts —
both in the safe direction. Recorded rather than worked around: minting a kind
for it is a type-system change, not an operator one.

### The FPC seed canary caught the landing

`pasparser_call.inc` called `StringTypeNameKind` whose body is later in the
single-pass seed. `make compiler/pascal26` and `--tier quick` both passed;
`gate.sh quick`'s canary is the only instrument that sees it. Forward
declaration added beside `BuiltinTypeNameTk`'s, which exists for the same
reason.

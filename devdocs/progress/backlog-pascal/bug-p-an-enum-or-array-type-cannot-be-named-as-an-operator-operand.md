---
slug: bug-p-an-enum-or-array-type-cannot-be-named-as-an-operator-operand
track: P
prio: 30
type: bug
status: backlog
owner: ""
created: 2026-09-09
found-by: frankH
blocked-by: []
summary: "`operator ** (a, b: TEnum)` and `operator and (a, b: TArr)` answer `<name> is not a supported operand type`: OperandTypeKindRec resolves a name through IsRecordType, FindUClass, BuiltinTypeNameTk, StringTypeNameKind and FindTypeAlias, and an ENUM type is in none of them while an ARRAY type is deliberately in none. Measured 2026-09-09 with the 209-cell probe after the predefined-table fix landed: of the 117 cells fpc accepts, pxx now accepts 106, and ALL ELEVEN remaining are the TEnum column -- every one failing at the operand-NAME door, not at the predefined check. The enum half is blocked on something bigger than a lookup: pxx has no tyEnum, so an enum operand would carry an integer kind and `*`/`/` on an enum pair would answer predefined where fpc accepts (safe direction, but it means the column can never be exactly right without a type-system change). toperator78 needs the array half."
---

# An enum or array type cannot be named as an operator operand

```pascal
type
  TEnum = (eA, eB, eC);
  TArr  = array of Char;
operator ** (left: TEnum; right: TEnum) res : LongInt;   { not a supported operand type }
operator and (left: TArr;  right: TArr)  res : LongInt;   { not a supported operand type }
```

`OperandTypeKindRec` (`pasparser_call.inc:26`) resolves an operand type name
through, in order: `IsRecordType`, `FindUClass`, the hand-written
`string`/`ansistring` pair, `BuiltinTypeNameTk`, `StringTypeNameKind` and
`FindTypeAlias`. An enum type is in none of them. An array type is
deliberately in none — its own comment says so.

## Why this is the whole of the remaining gap, and how that was measured

After [[bug-p-the-operator-predefined-check-is-an-aggregate-approximation]]
replaced the aggregate rule with the measured table,
`tools/operator_predefined_matrix_probe.py` reports:

| | cells |
| --- | --- |
| fpc accepts | 117 |
| pxx accepts | 106 |
| still refused | 11 — **all of them TEnum** |

Every one of the eleven is refused at the NAME door and never reaches the
predefined check, so no amount of work on the table moves them.

## The two halves are not the same size

**The array half is a lookup.** `TArr` has an alias row; it is excluded because
the operand table has no array entry, and tarray18's `array of LongInt`
operand is the same gap. toperator78 declares `operator and (left, right:
TTests)` over two `array of Char` operands and needs this.

**The enum half is a type-system question wearing a lookup's clothes.** pxx has
no `tyEnum` — an enum carries an integer kind. Resolving the NAME is easy; the
consequence is that `operator * (a, b: TEnum)` and `operator / (a, b: TEnum)`
would then be refused as predefined, because integer `*` and `/` are, while fpc
accepts both. That is the safe direction — a refusal fpc would not raise is a
compat gap, never an overload shadowing a builtin — but it means **the TEnum
column cannot be made exactly right without minting a distinct kind**, and that
is a change to the type system rather than to operator overloading.

So the honest options are: resolve the name and accept two wrong cells in the
safe direction, or mint `tyEnum` and do it properly. Worth deciding before
writing either.

## Related, and NOT the same message

`tforin15` fails with the same `is not a supported operand type` text for
`Twice = type Integer`, and is **not** fixed by widening this: resolving
`Twice` to `tyInteger` makes it collide with the `operator enumerator(Integer)`
declared beside it. A distinct scalar type has no identity in a table keyed on
`(typeKind, recId)` — see
[[bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct]]. One
message, three rows, three different causes underneath it.

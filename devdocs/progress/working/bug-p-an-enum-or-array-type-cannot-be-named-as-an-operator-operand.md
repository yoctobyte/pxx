---
slug: bug-p-an-enum-or-array-type-cannot-be-named-as-an-operator-operand
track: P
prio: 30
type: bug
status: working
owner: frankH
created: 2026-09-09
found-by: frankH
blocked-by: []
summary: "THE ARRAY HALF IS DONE; the ENUM half is open and is a type-system question, not a lookup. A NAMED array type is now a legal operand type -- `operator and (a, b: TArr)` over `array of Char` and `operator + (a, b: TNums)` over `array of LongInt` both compile and fire, fpc-identical on five targets. The ticket said the array half was 'a lookup' and that was MEASURED WRONG: an array's TypeKind IS its element kind, so registering TArr under tyChar makes it the SAME (kind, recId) row as Char -- with both declared, `c and d` on two Chars ran the ARRAY body and segfaulted inside Length. It took a REC_ARRAY_OPERAND key and FOUR consumers of the same fact: the operand NAME door, the use-site KEY (OperandRecOfNode), the declaration-time PREDEFINED check, and the use-site overload GUARD (OperandPairMayOverload, which now also has one spelling instead of two copies). toperator78's wall moved from line 9 to line 19 and the row stays skipped; tarray18 is NOT covered -- its operand is an anonymous `array of LongInt` in an open-array PARAMETER, a different shape. The enum half still needs tyEnum: pxx has none, so `operator * (a, b: TEnum)` would be refused as predefined where fpc accepts, and the column cannot be exactly right without minting a kind."
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


## 2026-09-09 (frankH) — the array half, and the premise that was wrong

**"The array half is a lookup" was this ticket's own claim and it is false.**
The lookup part is two lines: `FindArrayType(nm)` and `ArrTypeElemTk[ai]`. With
only that, `operator and (a, b: TArr)` over `array of Char` compiles and fires
correctly — and then this happens:

```pascal
operator and (const a, b: TArr) res: LongInt;   { array of Char }
operator and (const a, b: Char) res: LongInt;
...
n := c and d;      { two Chars -> ran the ARRAY body -> SIGSEGV inside Length }
```

An array's TypeKind IS its element kind, so `array of Char` and `Char` are the
same `(kind, recId)` row in a table keyed on those two. pxx's own
`operator is already overloaded for these operand types` warning fired at the
declaration and named the collision; the crash was the use site taking the
first row. fpc 3.2.2 runs both correctly.

`REC_ARRAY_OPERAND` (negative, so it can never collide with a real rec id)
separates them. **Four consumers of "an array is not its element" had to learn
it**, and each failed differently and silently:

| consumer | what it did instead |
| --- | --- |
| the operand NAME door (`OperandTypeKindRec`) | `TArr is not a supported operand type` |
| the use-site KEY (`ResolveNodeRec` at nine sites) | matched the ELEMENT's row |
| the declaration PREDEFINED check | refused `+` on `array of LongInt` as integer `+` |
| the use-site overload GUARD | asked `OperationIsPredefined` about integer `+`, got True, and never looked in the table — so the declaration was accepted and the use site silently took dyn-array concatenation, printing 124286578720984 where fpc prints 405 |

Two of those are now spelled ONCE — `OperandRecOfNode` for the key (nine call
sites across three files) and `OperandPairMayOverload` for the guard (which
stood copied at two). The fifth site, `CheckArithOperandsHaveAMeaning`'s
dyn-array refusal, needed the overload test too: its header said "an overloaded
operator is a call and never reaches here", which is true of records and of
concatenation and NOT of an array operator, whose arm retypes the node without
`continue`ing.

### What moved and what did not

- **toperator78**: wall moved from line 9 to line 19. Still skipped — the new
  wall is a MIXED-operand predefined row (`operator + (LongInt, AnsiString)`,
  reported one declaration late), which belongs to
  [[bug-p-the-operator-predefined-check-is-an-aggregate-approximation]].
- **tarray18 is NOT covered.** Its operand is `array of LongInt` spelled inline
  in an open-array PARAMETER, not a named type — the name door never sees a
  name. Different shape, still open.
- **The predefined matrix probe is unchanged** and cannot move: its 209 cells
  are ten SCALAR type columns with no array column, so the eleven remaining
  refusals are the TEnum column exactly as before.

### One accidental cover removed, and it is filed

With `operator + (a, b: TRec)` declared, `p + q` over two `array of TRec` used
to be REFUSED — by the operator lookup matching the RECORD operator for an
array operand (`ResolveNodeRec` answers with the element's record), retyping
the node, and the dyn-array arm then firing. A right answer from a wrong match.
Keying array operands separately removes the wrong match and with it that
error, leaving the shape consistent with the identical program that has no
operator declared — which the PIN also accepts. So the underlying gap is
pre-existing and deliberate (`AssignSideKind` abstains on any dyn-depth side),
and it is filed as
[[bug-a-a-dynamic-array-value-can-be-assigned-to-a-record-variable]] with the
pin control.

### Still open here: the enum half

Unchanged and unstarted. `TEnum` is all eleven remaining probe cells, pxx has no
`tyEnum`, and resolving the NAME alone would make `operator * (a, b: TEnum)`
and `operator / (a, b: TEnum)` refuse where fpc accepts — the safe direction,
but the column cannot be exactly right without minting a kind. The array half's
lesson applies directly: a key that cannot express the distinction produces a
COLLISION, not a refusal, and the collision is the dangerous half.

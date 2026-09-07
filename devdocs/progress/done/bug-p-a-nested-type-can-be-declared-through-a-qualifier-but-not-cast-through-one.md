---
slug: bug-p-a-nested-type-can-be-declared-through-a-qualifier-but-not-cast-through-one
title: "`TOwner.TNested(x)` and `inst.TNested(x)` are refused: a nested type resolves in a DECLARATION and in SizeOf/Low/Default, but not in a TYPECAST"
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-07
summary: "`var f: TPlain.TPFn` compiles and `SizeOf(TPlain.TPFn)`, `SizeOf(TPlain.TPRange)` and `Low(TPlain.TPRange)` all answer correctly, but the CAST spelling of the same name is refused two different ways: `TPlain.TPFn(@Cmp)` gives `class method not found (TPFn)` (the class-MEMBER walk, for a type that exists three lines above) and `p.TPFn(@Cmp)` gives `\"TPFn\": no such member on this record/class`. NOT GENERIC-SPECIFIC -- measured on a plain non-generic class, identical on pin v407. This is the FIFTH ABSENT COPY of EatQualifiedTypePrefix, which is exactly what that function's own comment predicts (\"a rule spelled per call site fails by an ABSENT copy, and absent copies agree with each other perfectly\"); the four it names are ParseTypeKindInner, SizeOf, Default and Low/High, and a TYPECAST is a fifth position nobody enumerated. THE TRAP FOR WHOEVER TAKES IT: do NOT key the guard on FindNestedType. AddNestedType exits when ci < 0, so a nested PROCEDURAL, subrange, enum or array type has NO registry row at all and FindNestedType(TPlain, 'TPFn') is -1 -- EatQualifiedTypePrefix resolves it anyway, through the QualTypeOwnerCi channel into the alias lookup. A guard copied from EatQualifiedNestedClassRef would compile, look right, and reject every non-class nested type, which is the whole population here. Walls tgeneric10.pp."
---

# Repro — a plain class, no generics anywhere

```pascal
program q4; {$mode objfpc}{$H+}
type
  TPlain = class
  type
    TPFn = function(const a, b: LongInt): LongInt;
    TPRange = 1..9;
  end;
function Cmp(const a, b: LongInt): LongInt; begin Result := b - a; end;
var p: TPlain; f: TPlain.TPFn;
begin
  p := TPlain.Create;
  f := @Cmp;
  WriteLn('declType = ', f(1, 9));                 { works        }
  WriteLn('castType = ', TPlain.TPFn(@Cmp)(1, 9)); { class method not found (TPFn) }
  WriteLn('castInst = ', p.TPFn(@Cmp)(1, 9));      { "TPFn": no such member        }
end.
```

fpc 3.2.2 prints `8` three times. pxx and pin v407 both stop at the first cast.
Measured 2026-09-07 at compiler `cd30ba1c7d5d`.

# What already works, which is what localises it

| spelling | pxx |
| --- | --- |
| `var f: TPlain.TPFn` | works |
| `SizeOf(TPlain.TPFn)` | 8, matches fpc |
| `SizeOf(TPlain.TPRange)` | 1, matches fpc |
| `Low(TPlain.TPRange)` | 1, matches fpc |
| `TPlain.TPFn(@Cmp)` | `class method not found (TPFn)` |
| `p.TPFn(@Cmp)` | `"TPFn": no such member on this record/class` |

So the NAME resolves; only the CAST position does not know how to reach it. Two
positions, two different messages, because each falls through to a different
walk — the class-member walk in `ParseLValueAST` and the selector walk in
`ParseClassRecordSelectors`.

# The pattern this belongs to

`EatQualifiedTypePrefix` (pasparser_class.inc) is the one copy of the
`TOwner.`-strip, and its own comment records that the rule previously existed
per call site and **failed by an absent copy** four times:
`ParseTypeKindInner`, `SizeOf`, `Default` (found by a `tdefault8` segfault) and
`Low`/`High`. `EatQualifiedNestedClassRef` then added three more positions —
the ancestor list, and the right operand of `is` and `as` — each of which had
answered `expected ')' before '.'`.

**A TYPECAST is the next position, and it is two sites rather than one.** The
comment's own remedy applies: it was found *"by a probe drawn from the GRAMMAR
rather than from any helper's call graph, which by construction only returns
sites that already reach the helper."* Every position where a TYPE NAME may
appear is the population; a cast is one, and the instance-qualified cast is one
the grammar allows and nothing had enumerated.

# The trap, and it is the reason this ticket is worth its length

**Do not key the guard on `FindNestedType`.** `AddNestedType` begins:

```pascal
if (ownerCi < 0) or (ci < 0) then Exit;
```

so a nested **procedural, subrange, enum or array** type never gets a registry
row, and `FindNestedType(TPlain, 'TPFn')` is `-1`. `EatQualifiedTypePrefix`
resolves those anyway: when `ScanNestedTypeRun` answers -1 it sets
`QualTypeOwnerCi := NestedOwnerCi(name)` and lets the ordinary alias lookup find
the member among that owner's rows. Its own comment says so.

`EatQualifiedNestedClassRef` DOES guard on `FindNestedType` — correctly, because
its callers want a class ROW. Copying that guard here would compile, read as
careful, and reject every non-class nested type, which is the entire population
this ticket is about. **A guard drawn from the sibling would be a guard that
cannot fire.**

# To burn

`tgeneric10.pp` — `ilist.sort(ilist.TCompareFunc(@CompareInt))`, the
instance-qualified spelling. That row's skip reason blames "objfpc
generic/specialize syntax + nested type of a specialization"; the generics are
incidental and the reason should be corrected when this lands.

Also worth a row in whatever fixture results: the same cast through a
SPECIALIZATION's alias (`TI.TFn(@Cmp)` where `TI = specialize TBox<LongInt>`),
which fails the same two ways — so the fix should be measured on both the plain
and the specialized receiver, and neither is harder than the other once the
strip is in place.

# FIXED — and it was one absent copy, not two sites

`ClassDeclaresTypeNamed` and `TryNestedTypeCastOnReceiver` (pasparser_class.inc)
plus the `TOwner.TNested(` strip in `ParseFactorCore`. All measured against
fpc 3.2.2; fixture `test/test_a_nested_type_can_be_cast_through_its_qualifier.pas`,
fifteen rows, `test_qualcast26`.

**The population was wider than the ticket's two rows and it is one cause.**
Measured before the fix on a plain non-generic class: ALL SEVEN nested kinds
were refused in a cast — procedural, subrange, enum, array, class, record and
plain alias — through BOTH spellings. Six rows now match fpc; the seventh
(record) needs a `^` and is exercised elsewhere.

**The trap this ticket wrote down was real and it was not the whole trap.**
Keying the guard on `FindNestedType` would have rejected everything, as
predicted. But the Alias\* table — where a nested procedural, subrange and plain
alias DO live, owner-scoped through `AliasOwnerCi` — does not hold the other
two: `EnumType*` and `ArrType*` **carry no owner column at all**, so the
owner-scoped question cannot even be asked of a nested enum or a nested named
array. With the scoped test alone, five of seven kinds resolved and two stayed
refused, which is exactly the five-of-seven shape a per-table rule produces.
Those two are answered UNSCOPED, matching the decision `FindNestedClassLikeCi`'s
header already records for the class-alias table.

**That widening is what makes rows 11-14 of the fixture load-bearing.** An
unscoped fallback admits `TFoo.Bar(x)` where `Bar` is a global enum or array
type AND `TFoo` has a member of that name, so members are checked FIRST. The
fixture asserts it with a class function called `TColor` beside a global
`TColor` enum: with that one line removed and nothing else changed, `shadow=`
and `ishad=` print **5** — the cast's answer — instead of 502. Both control
rows return `x*100+k` deliberately, because `TColor(5)` and `Ident(5)` would
both have printed 5 and **the control could not have failed.**

**ParseFactor got the save/restore wrapper** that `TryConstHighLowValue` and
`TryFoldHighLowType` each carry, because `QualTypeOwnerCi` has to survive INTO
the cast arms and not out of them. It closes two PRE-EXISTING leaks as a side
effect — `Default()`'s and `SizeOf()`'s strips both set the global and neither
restored it — and that is named in the code rather than left silent.

`ParseFactor`'s forward MOVED to `frontend_forwards.inc`, not copied there:
FPC's seed rejects a repeated forward exactly as hard as a missing one, and pxx
tolerates both, so either mistake is invisible to `make compiler/pascal26`.

## Burned
`tgeneric10.pp` — row removed. Compiles, runs, prints `ok`, matching fpc 3.2.2
run for run (not read off the exit code: tgeneric16 is the standing reminder).

## Two adjacent gaps this measured and did NOT fix
- `var a: TOwn.TPArr` — a nested named ARRAY in a DECLARATION is refused
  (`this value cannot be indexed`), while the unqualified `var a: TPArr` and the
  nested RECORD spelling both work. Filed as
  `bug-p-a-nested-array-type-is-refused-in-a-qualified-declaration`.
- `TPlain.TPCls.ClassName` answers `TPCls` where fpc answers `TPlain.TPCls`.
  Not filed: a nested class's qualified RTTI name is a separate subject and no
  row in tree depends on it. Noted so the next reader does not re-measure it.

## Log
- 2026-09-07 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 8d87d3e8e.

---
slug: bug-p-a-nested-type-can-be-declared-through-a-qualifier-but-not-cast-through-one
title: "`TOwner.TNested(x)` and `inst.TNested(x)` are refused: a nested type resolves in a DECLARATION and in SizeOf/Low/Default, but not in a TYPECAST"
track: P
prio: 55
type: bug
blocked-by: []
status: open
owner: ""
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

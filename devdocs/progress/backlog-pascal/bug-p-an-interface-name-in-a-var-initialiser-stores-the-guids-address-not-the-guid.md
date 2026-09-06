---
track: P
prio: 60
type: bug
blocked-by: []
status: open
owner: frankS
---

# An interface name in a var initialiser stores the GUID's ADDRESS, not the GUID

An interface type name used as a value means its GUID — `defs.inc:965`,
`AN_GUIDCONST`, *"which in Pascal means exactly one thing, its GUID"*. That
works in a statement and is silently wrong in a var initialiser.

Measured 2026-09-06 at compiler `cda68a91bec5`, `{$mode objfpc}`, on
`ICom = interface ['{04B6AB72-8F86-45F8-8D49-393E799F51A8}']`, printing the
first eight bytes of the destination:

| form | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `h := ICom` (statement) | `114 171 182 4 134 143 248 69` | same |
| `var g: TGUID = ICom` | **`248 27 65 0 0 0 0 0`** | `114 171 182 4 134 143 248 69` |
| `const g: TGUID = ICom` | `expected '(' before 'ICom'` | compiles, correct bytes |

`114 171 182 4` is `04B6AB72` little-endian — the right answer, which the
statement path produces. **`248 27 65 0 0 0 0 0` is `0x00411BF8`: an address.**
`AN_GUIDCONST`'s own doc says lowering *"yields that blob's data address"*, and
the var-initialiser path stores that pointer into the record instead of copying
the 16 bytes behind it.

## Why it ranks at 60 rather than as a missing arm

It is a **silent wrong value in interface identity**. `TObject.GetInterface`
looks an interface up BY GUID at runtime (`defs.inc:447`), so a `TGUID` global
seeded this way holds an address where 16 bytes of identity belong, and every
comparison against it fails — or, worse, succeeds against whatever else happens
to sit at that address pattern. Nothing diagnoses it: the declaration compiles,
the record is the right size, and the program runs.

The refusal on the `const` line is the *better* of the two failures, and note
which one a user hits: `const` is the spelling this construct is normally
written in, so the shape that stays quiet is the one people reach for second,
after the diagnostic pushes them off the first.

## The pattern this completes, which is the reason to fix both together

Four cells: two value forms crossed with two initialiser paths. Three are wrong,
in three different ways, and the two paths fail in OPPOSITE directions:

| value form | `const X: T = ...` | `var X: T = ...` |
| --- | --- | --- |
| `@Something` | worked | **was refused** — fixed at `21ac9e7bc` |
| an interface name | **refused** | **accepts, stores a pointer** |

The `@` row was fixed this morning by making the var path call the same helper
the const path already used. This row wants the mirror, and the strongest
argument for one shared path is that nobody could have predicted which
direction each asymmetry ran — they are not a systematic "const is ahead of
var", they are two independent omissions that happen to point opposite ways.

## Also absent, found in the same file and not fixed here

`IsEqualGUID` is not in `lib/rtl/sysutils.pas` (zero hits). That is Track B and
a separate row; `tinterface6.pp` needs it as well as the two arms above, which
is why that conformance row takes three changes across two lanes and is not a
single burn.

## Repro

```pascal
{$mode objfpc}
type ICom = interface ['{04B6AB72-8F86-45F8-8D49-393E799F51A8}'] end;
var g: TGUID = ICom; i: Integer;
begin for i := 0 to 3 do Write(PByte(PtrUInt(@g) + i)^, ' '); end.
{ fpc: 114 171 182 4     pxx: 248 27 65 0 }
```

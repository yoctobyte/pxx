---
track: P
prio: 60
type: bug
blocked-by: []
status: done
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

# RESOLVED — all four cells, and the fix found a fifth the ticket did not list

The ticket's table has four cells (two value forms x two initialiser paths).
Working it turned up a **fifth axis it does not mention: global vs
routine-local**, which is a genuinely separate emitter, and the first version of
this fix compiled clean and SIGSEGV'd on it.

## Cause, and it is the one the statement path already fixed

Not an "address instead of a copy" in the GUID lowering. **The var-section
initialiser's METACLASS arm claimed the name.** Its guard is `tkIdent` +
`IsClassType` + not-a-symbol, an interface satisfies all three, and the arm
records init kind 5 — an `AN_CLASSREF` VMT address. `0x00410BD8` was never a
GUID pointer; it was a class reference.

That is precisely
`bug-a-an-interface-name-as-a-guid-value-copies-rtti`, one construct over: there
the statement path fell through to `AN_CLASSREF` and *"made the record copy read
16 bytes of the RTTI blob... with no diagnostic and a plausible-looking result"*.
Fixed the same way, by asking about interfaces FIRST — now through a named
`IsInterfaceTypeName`, because it is two lookups and the second is the easy half
to forget at the next site.

## Kind 10, not a new baked shape

`PendingInitKind` 10 already means *"Val IS AN AST NODE INDEX"*, and its own
declaration says why it exists: the other kinds name a constant the emitter
rebuilds in `Data[]`, and this one keeps the AST so the initialiser runs at
program entry *"like the assignment it is"*. `g := ICom` as a statement has
always produced the right bytes — an ordinary 16-byte record copy from the
interned blob — so the fix hands that working path the same node rather than
teaching a second one to bake a GUID. Both sections inherit it because both call
`TryParseInitValForm`, which is exactly how the `@` half of this table was fixed
at `21ac9e7bc`.

## The fifth cell, which is the part worth reading

`FlushLocalInits` is a **separate emitter** and knew kinds 1/2/4/5/9. Its `else`
is a silent catch-all that builds an `AN_INT_LIT` from whatever `Val` held — so
a routine-local `var g: TGUID = ICom` assigned a *node index* into a TGuid and
the program **segfaulted**, while the compile printed `ok`. Measured, not
predicted: the fixture's local rows are what caught it.

**A kind the global emitter knows and the local one does not is not a missing
feature there, it is a wrong value.** Kind 10 added to the local emitter with
that written beside it.

The const branch is dedicated rather than a widening of the general const path,
and deliberately: letting a record-typed const fall through would hand LOCAL
consts to `TryParseInitValForm` for the first time, whose string arm keys on the
destination type — so `const S: ShortString = 'x'` inside a routine would move.
That is a separate extent to enumerate.

## Verification

`test/test_interface_name_as_guid_initialiser.pas`, wired into `test-core`,
`.expected` generated from fpc 3.2.2. Five rows, all byte-identical: statement,
global var, global const, local var, local const.

**The statement row is the control** — it was always correct, so a fixture
without it would pass if every declaration broke the same way. **Eight bytes are
the assertion**, not a `<> nil` or a size: `114 171 182 4` is `04B6AB72`
little-endian; an address shows as a small number followed by zeros, which is
what made the original defect invisible to any check that only asked whether
something was stored.

Control run, not assumed: with all four compiler files reverted, the fixture does
not compile (`expected '(' before 'ICom'` at the global const). Self-host
fixedpoint converged (`a7b03135f504`).

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2cf3b41c0.

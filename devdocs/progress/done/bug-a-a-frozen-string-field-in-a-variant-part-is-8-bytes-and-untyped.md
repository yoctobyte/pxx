---
track: A
prio: 55
type: bug
blocked-by: []
owner: claude-A
status: done
---

# A `string[N]` field in a record's VARIANT part is 8 bytes and reads as an address

- **Type:** bug (silent wrong value **and** a record-sized buffer overrun) — **Track A**
- **Found:** 2026-08-10 by an FPC differential over the variant-record /
  typed-constant / `with` / nested-procedure surface.
- **Pre-existing:** identical on `pinned`.

```pascal
type
  TKind = (kInt, kStr);
  TVar = record
    id: Integer;
    case k: TKind of
      kInt: (iv: Integer);
      kStr: (sv: string[6]);
  end;
var v: TVar;
begin v.sv := 'aa'; WriteLn(v.sv); end.
```

FPC prints `aa`. pxx printed **`4243311`** — an address. Every access route was
equally wrong (scalar, array element, through `with`), and so was `Length`.

## Two faults, one absent code path

`ParseRecordVariantPart` had **no frozen-string arm at all**, while the record's
FIXED-part builder a few hundred lines away has one:

1. **Size.** The branch got `TypeSize(tyFixedString)` = 8 rather than
   `FrozenStrSlotSize`. A `case` with a `string[40]` branch measured **16 bytes**
   where that field alone needs 48 — so writing the field ran off the end of the
   record. This is the serious half: it corrupts whatever follows.
2. **Type.** It was registered as `Ord(tyFixedString)`; the fixed part registers
   `Ord(tyString)` with `UFldStrCap` carrying N, which is what the read/write
   codegen and the truncating store both expect. Hence the address.

Every OTHER branch type was already correct — Integer, Double, Char, Boolean, a
fixed array, a nested record — and `SizeOf` of the record in my first probe
matched FPC anyway, because the `Double` branch happened to be the largest. The
one type that needed a second code path is the one that did not get it.

Textbook [[feedback_root_cause_over_microfix]] shape: **two spellings of one
thing, one of them tested.** The fix is to mirror the fixed-part arm, not to
patch the read site.

## Fixed

`ParseRecordVariantPart` now dispatches `tyString` / `tyFixedString` /
`tyShortString` exactly as the fixed part does, and registers a frozen-string
branch as `tyString` + `UFldStrCap`.

## Verified

All rows diffed against `fpc -O1` (`{$mode objfpc}`), and all of them are wrong
on `pinned`:

- read/write/`Length` through a scalar, an array element, and `with`;
- truncation at the declared capacity;
- the overlay still overlays (writing the other branch changes these bytes);
- no overrun into the next array element after filling the string to capacity.

`test/test_variant_part_string_field.pas`, asserted in the Makefile.
**SizeOf is deliberately not asserted against FPC** — pxx's frozen string is
`[len:8][chars:N]` and FPC's is `[len:1][chars:N]`, so the numbers differ for
the same correct layout; the overrun row states the property behaviourally
instead.

`tools/gate.sh quick` GREEN, self-host fixedpoint converged in 1 round.

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.

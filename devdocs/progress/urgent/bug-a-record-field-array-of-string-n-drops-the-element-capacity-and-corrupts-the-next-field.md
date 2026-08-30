---
track: A
prio: 72
type: bug
blocked-by: []
summary: "A record field of type `array[0..1] of string[8]` stores UNCLAMPED: `r.a[0] := 'abcdefghijkl'` keeps all 12 characters where FPC keeps 8, and a longer store CORRUPTS THE NEIGHBOURING FIELD — a 26-character store changed an adjacent Integer field from 12345 to 31353. The identical array as a global, a local, a by-value parameter or a function result all clamp correctly, and a plain `s: string[8]` field clamps correctly. Only the array-element capacity, only on the record-field path."
status: new
owner: ""
---

# A record field `array[..] of string[N]` drops N and overruns into the next field

- **Type:** bug — **Track A** (the `UFld*` field-carrier family lives in
  `defs.inc`/`symtab.inc`; the write site is `pasparser_decl.inc`, which is
  Track P's file — see *Where the fix goes*).
- **Found:** 2026-08-30 by frankwasm, cross-checking the array-element carrier
  set while planning `feature-unicodestring-model` step 6b. Not part of that
  work: this is wrong on `pinned` today.
- **This writes outside the field.** Treat it as a corruption bug, not a
  string-length bug.

## Measured, against FPC 3.2.2

Five shapes of the same type, one wrong:

```pascal
type TA = array[0..1] of string[8];
```

| the array is a… | FPC | pxx |
| --- | --- | --- |
| global `g: TA` | `abcdefgh` (8) | `abcdefgh` (8) |
| local `lv: array[0..1] of string[8]` | `abcdefgh` (8) | `abcdefgh` (8) |
| by-value parameter | `abcdefgh` (8) | `abcdefgh` (8) |
| function result | `abcdefgh` (8) | `abcdefgh` (8) |
| **record FIELD `r.a[0]`** | `abcdefgh` (8) | **`abcdefghijkl` (12)** |

And it is the ARRAY ELEMENT's capacity specifically, not the field path in
general — a plain frozen field is fine:

| field shape | FPC | pxx |
| --- | --- | --- |
| `record s: string[8] end` | `abcdefgh` (8) | `abcdefgh` (8) |
| `record a: TA end` (named alias) | `abcdefgh` (8) | **`abcdefghijkl` (12)** |
| `record a: array[0..1] of string[8] end` (inline) | `abcdefgh` (8) | **`abcdefghijkl` (12)** |

## The corruption

```pascal
type TR = record a: array[0..1] of string[8]; tail: Integer; end;
var r: TR;
begin
  r.tail := 12345;
  r.a[1] := 'ZZZ';
  r.a[0] := 'abcdefghijklmnopqrstuvwxyz';   { 26 chars into a cap-8 element }
```

| read back | FPC | pxx |
| --- | --- | --- |
| `r.a[0]` | `abcdefgh` | `abcdefghijklmnopqrstuvwxyz` |
| `r.a[1]` | `ZZZ` | `ZZZ` |
| **`r.tail`** | **`12345`** | **`31353`** |

The store runs past the field and rewrites the neighbouring `Integer`. No error,
no bounds complaint. `r.a[1]` surviving while `tail` is clobbered is recorded as
measured — **do not build a layout theory on it without a probe**; the point
here is the observable, which is that a declared `string[8]` accepted 26
characters and the damage landed outside the array.

## Cause — suspected, NOT confirmed. Probe before recording one.

This has the exact shape of the `LastType*` staleness class documented at the
head of the `LastType*` block in `defs.inc`: a per-entity carrier that some
declaration paths capture and one does not. `ArrTypeElemStrCap` exists precisely
to carry an array's frozen-string element capacity across the gap between where
`string[N]` is parsed and where the array type is used, and its own comment says
so. The field path appears not to consult it — there is no `UFld` twin of it in
the field-carrier family, where `UFldPtrElemTk`, `UFldEnumId` and `UFldStrElemTk`
all exist.

Confirm with `PXXDBG` and by checking whether `AddUField` ever sees the element
capacity, before writing a cause into this ticket. Every wrong root cause in
this repo was a plausible story nobody diffed against an oracle.

## Where the fix goes

Most likely a `UFldElemStrCap` carrier beside the existing `UFld*` element
carriers — `defs.inc` and `symtab.inc` are **Track A**, and the write site at
the field declaration is in `pasparser_decl.inc`, which is **Track P's** file.
Coordinate if two agents hold those concurrently. If the fix turns out to be
entirely inside the parser, re-file it as Track P.

## Why it was not found before

The four shapes that work are the four anyone writes a test for. The record
field is the one that needs the value to survive *two* hops — `string[N]` into
the array type, then the array type into the field — and it is the only shape
where both hops happen.

## Gate

`make compiler/pascal26` + the three programs above matching FPC on every row,
`r.tail` included.

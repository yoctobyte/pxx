---
track: A
prio: 72
type: bug
blocked-by: []
summary: "A record field of type `array[0..1] of string[8]` stores UNCLAMPED: `r.a[0] := 'abcdefghijkl'` keeps all 12 characters where FPC keeps 8, and a longer store CORRUPTS THE NEIGHBOURING FIELD — a 26-character store changed an adjacent Integer field from 12345 to 31353. The identical array as a global, a local, a by-value parameter or a function result all clamp correctly, and a plain `s: string[8]` field clamps correctly. Only the array-element capacity, only on the record-field path."
status: done
owner: frankwasm
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


## RESOLVED 2026-08-30 (frankwasm) — a sibling arm that was never written

**Cause, confirmed rather than suspected.** The suspicion in this ticket was
wrong in an instructive way: I guessed a missing `UFld` twin of
`ArrTypeElemStrCap`, i.e. that the DECLARATION dropped the capacity. It does
not. `SizeOf` proves the layout knows it — a record of cap-8 elements is 40
bytes and the identical record of cap-200 elements is 424, a difference of
exactly 2x192. The element slots are sized by the declared N, so `UFldStrCap`
holds 8 and every carrier on the declaration side is intact.

The defect is in the STORE clamp, `ir.inc` AN_ASSIGN, which had exactly two arms:

    r.s   := s      AN_FIELD                  -> RecFieldStrCap    (present)
    a[0]  := s      AN_INDEX over AN_IDENT    -> SymStrCap         (present)
    r.a[0]:= s      AN_INDEX over AN_FIELD    -> nothing           MISSING

So `lhsStrCap` stayed 0 and the copy took the SOURCE length. The neighbour of a
record field being the next field is why it presented as corruption rather than
a long string.

**The arm that exists carries a comment describing this exact bug** — *"Without
it `a[0] := s` copied the SOURCE length — writing past the element's N chars
into its neighbour"* — written when the SYMBOL case was fixed. The field case
was not grepped for. That is precisely the rule in CLAUDE.md and
`devdocs/dev/normalise-dont-special-case.md`: **if you fix a bug on one arm of a
double case, grep for the sibling before closing the ticket.** This ticket is
the cost of not doing it.

**Fixed by asking the question in one place**, not by adding a third arm:
`FrozenStrElemCapOf(base)` in `ir.inc` answers "the frozen-string element
capacity of this index base" for both an array SYMBOL and an array FIELD, and
the single `AN_INDEX` arm calls it. A third parallel arm would have been the
same mistake a third time.

**Two more broken shapes fell out of the one fix**, both confirmed broken on
`pinned` and correct after — neither was in the original report:

    o.inner.a[0] := LONG    nested record field
    ar[0].a[0]   := LONG    field of an array-of-record

A dynamic `array of string[N]` was already correct and stays so.

**Regression test:** `test/test_frozen_str_array_elem_cap.pas`, covering all
eleven shapes including the four that always worked (so a future fix cannot
regress them) and the corruption assertion itself — `tail` reading 12345. Its
`.expected` was generated from **FPC**, then diffed against our output; it is an
oracle file, not a recording of what we happen to print.

Gate: `make compiler/pascal26` converged in 1 round (8a9e78fb4555); all four
differential programs match FPC.

## Log
- 2026-08-30 — resolved, commit 6e25bdcde.

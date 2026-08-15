---
track: B
prio: 40
type: bug
blocked-by: []   # the compiler half landed 2026-08-15 as --strict-overload-width
summary: "`IntToHex(-1, 8)` prints FFFFFFFFFFFFFFFF where FPC prints FFFFFFFF: lib/rtl/sysutils declares only the Int64 overload, so a 32-bit Integer argument is sign-extended to 64 bits and renders eight extra F's. Positive values agree, so it only shows on negatives — where hex is most often used"
---

# `IntToHex` of a negative Integer prints 16 digits, not 8

- **Type:** bug (wrong output) — **Track B** (`lib/rtl/sysutils.pas`)
- **Found:** 2026-08-12, differential bug hunting against FPC 3.2.2.

```pascal
var i: Integer;
begin
  i := -1;
  WriteLn(IntToHex(-1, 8));    { FPC: FFFFFFFF   pxx: FFFFFFFFFFFFFFFF }
  WriteLn(IntToHex(i, 8));     { FPC: FFFFFFFF   pxx: FFFFFFFFFFFFFFFF }
  WriteLn(IntToHex(i, 2));     { FPC: FFFFFFFF   pxx: FFFFFFFFFFFFFFFF }
end.
```

An `Int64` argument agrees (`FFFFFFFFFFFFFFFF` in both), and every positive
value agrees whatever its width, so the whole divergence is a negative value
whose declared type is 32-bit.

## Cause

`lib/rtl/sysutils.pas` declares one overload:

```pascal
function IntToHex(value: Int64; digits: Integer): AnsiString;
```

so an `Integer` argument is sign-extended into it and the top half's F's are
real digits by the time the routine sees the value. FPC declares the family
(`Byte`/`Word`/`Cardinal`/`Integer`/`Int64`…), and `digits` is a MINIMUM width
in both — which is why `IntToHex(i, 2)` still prints all of them rather than
truncating.

## The fix

Add the 32-bit overload (masking to `$FFFFFFFF` before rendering) beside the
Int64 one — and while there, the `Byte`/`Word`/`Cardinal` spellings FPC has, so
`IntToHex(b, 2)` on a byte cannot pick up sign extension either. Track A's
overload resolution already prefers an exact-width integer parameter over a
wider one ([[project_overload_resolution_single_side_channel_entry]]), so
adding the row is all that is needed.

## Gate

`make lib-test` plus a `.pas` diffed against FPC: -1 / -255 / MinInt as
`Integer`, the same values as `Int64`, positives of each width, `digits`
smaller and larger than the natural width, and a `Byte`/`Cardinal` argument.

## 2026-08-14 — half landed, half BLOCKED on the compiler (Track B)

### What landed

`lib/rtl/sysutils.pas` now declares the FPC family instead of one routine:

```pascal
function IntToHex(value: Int64;    digits: Integer): AnsiString; overload;
function IntToHex(value: LongInt;  digits: Integer): AnsiString; overload;
function IntToHex(value: LongWord; digits: Integer): AnsiString; overload;
```

The `LongInt` body masks with `Int64(LongWord(value))` before rendering, so the
widening that follows is zero-extension. A **`LongInt`** argument is now
FPC-correct: `-1` → `FFFFFFFF`, `MinInt` → `80000000`, `digits = 16` →
`00000000FFFFFFFF` (padded, not sign-extended).

### What is still wrong, and why the RTL cannot fix it

**An `Integer` argument still prints sixteen digits.** The ticket's "The fix"
section assumed Track A's resolution "already prefers an exact-width integer
parameter over a wider one". Measured — it does not:

| argument | pxx | FPC |
| --- | --- | --- |
| `LongInt` | longint ✓ | longint |
| `Integer` | **int64** | longint |
| `SmallInt` | **int64** | longint |
| `Byte` | **int64** | longint |
| literal `-1` | **int64** | longint |
| `Cardinal` | int64 ✓ | int64 |

`SizeOf(Integer) = SizeOf(LongInt) = 4`, and the `LongInt` row proves the narrow
overload is reachable — so selection keys on the type **NAME**, not the type,
and every spelling that is not literally `LongInt` widens to `Int64`.

Filed as **`bug-a-overload-resolution-widens-to-int64-instead-of-picking-the-narrowest-fit`**
with the full repro; this ticket is `blocked-by` it. Adding an `Integer`
overload beside the `LongInt` one would make the symptom go away today and is
exactly the compiler-appeasement CLAUDE.md forbids — in FPC they are one type,
so the declaration above IS the platonic one. Left in place.

### Measured against FPC 3.2.2

`{$mode objfpc}` is required in the oracle: in default FPC mode `Integer` is
**16-bit**, which silently answers a different question (it prints `00005678`
for `$12345678`). A `.pas` covering 14 rows — `Integer` / `Int64` / `Byte` /
`Word` / `Cardinal`, `-1` / `-255` / `MinInt` / positives, digits both under and
over the natural width — is the ticket's gate. Six rows still differ, all of
them `Integer`-typed or literal, all of them the blocker above.

`make lib-test` green with the family declared.

## 2026-08-14 (later) — re-framed: the remaining half is COMPAT, not a bug

The blocker was filed as `bug-a-overload-resolution-widens-to-int64-…` on the
assumption that selecting the wider overload was a defect. The user's call:

> *"this widening is not a bug. BUT it affects `--strict-fpc` mode"*

So the default dialect widening `Integer` into the `Int64` spelling is
**intended**, and `IntToHex(i, 8)` printing `FFFFFFFFFFFFFFFF` for an `Integer`
`-1` is the dialect's answer rather than a wrong one — the RTL is handed a
sign-extended 64-bit value and renders all of it, and `Digits` is a minimum in
both implementations.

What remains is therefore parity behind a flag, not a fix:
**blocked-by [[compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload]]**
(the renamed ticket, now `type: compat`, default behaviour explicitly unchanged).

The library half stands as landed and needs nothing further: the FPC family
(`Int64` / `LongInt` / `LongWord`) is declared, the `LongInt` body masks through
`LongWord()` so a `LongInt` argument answers `FFFFFFFF` / `80000000` /
`00000000FFFFFFFF` exactly like FPC, and that is what the flag will route
`Integer` arguments to. **No further `lib/rtl` change is expected here** — this
ticket is now a tracking placeholder for the strict-fpc row and could reasonably
be closed into the compat ticket instead.


## 2026-08-15 — UNBLOCKED: the compiler half landed (Track A)

`--strict-overload-width` implements FPC's narrowest-that-fits rule
(`compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload`). The RTL
side needed nothing further — the `Int64`/`LongInt`/`LongWord` family this
ticket already declared is the platonic one, and the `LongInt` body's mask is
what makes the answer right once that body is the one selected.

**This ticket's own 14-row FPC diff now passes verbatim under the flag** —
`Integer` −1/−255/MinInt/positive, `digits` 2 and 16, `Int64`, `Byte`, `Word`,
`Cardinal`, and the three literal rows — checked against FPC 3.2.2 under
`{$mode objfpc}`, byte-identical.

Without the flag `IntToHex(i, 8)` still prints `FFFFFFFFFFFFFFFF` for an
`Integer`, and that is **correct and intended**: the default dialect widens to
the widest overload by decision (user, 2026-08-14), so there is nothing left to
fix there. Verified unchanged against `pinned`.

What remains for Track B is a judgement call, not compiler work: whether to add
the ticket's 14-row `.pas` as a checked test, and if so which mode it asserts.
The Track A side ships its own two-way assertion already
(`test/test_strict_overload_width.pas`, run flagged and unflagged), whose last
row is exactly this `IntToHex` case.

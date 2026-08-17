---
track: B
prio: 40
type: bug
blocked-by: []   # the compiler half landed 2026-08-15 as --strict-overload-width
summary: "`IntToHex(-1, 8)` prints FFFFFFFFFFFFFFFF where FPC prints FFFFFFFF: lib/rtl/sysutils declares only the Int64 overload, so a 32-bit Integer argument is sign-extended to 64 bits and renders eight extra F's. Positive values agree, so it only shows on negatives — where hex is most often used"
status: done
owner: frank3
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

## 2026-08-17 — CLOSED: the 14-row diff is now a checked test (Track B, frank3)

The judgement call the previous note left open — whether to land the FPC diff as
a test, and in which mode — is resolved. **Both modes, in one program, split by
what each row actually proves.**

`test/lib_inttohex.pas` (new) is compiled twice by `make lib-test`:

```make
$(PXX_STABLE) -Fulib/rtl test/lib_inttohex.pas $(TESTTMP)/lib_inttohex
test "$$($(TESTTMP)/lib_inttohex | grep -c '=ok')" = "15"
$(PXX_STABLE) --strict-overload-width -dSTRICT_WIDTH -Fulib/rtl test/lib_inttohex.pas $(TESTTMP)/lib_inttohex_strict
test "$$($(TESTTMP)/lib_inttohex_strict | grep -c '=ok')" = "19"
```

* **15 rows assert the RTL BODIES and run unflagged.** Explicitly-typed
  `LongInt` / `LongWord` / `Int64` / `Byte` / `Word` arguments name their body
  directly, so these hold whatever the resolver does: the `LongInt` mask
  (`-1`→`FFFFFFFF`, `MinInt`→`80000000`, `digits=16`→`00000000FFFFFFFF`, i.e.
  zero-padded not sign-extended), `LongWord` zero-extension, `Int64` unchanged,
  and `digits`-as-a-MINIMUM in every body (`digits=2` on `-1` still prints all
  eight). **This is the part Track B owns**, and it is now regression-locked.
* **4 rows assert SELECTION and run only under `--strict-overload-width`**
  (`Integer`, `Integer` MinInt, `SmallInt`, bare literal `-1`), guarded by
  `STRICT_WIDTH`. Asserting them unflagged would freeze a **Track A** choice
  into a Track B test — and the default dialect's widening is intended (user,
  2026-08-14), so there is no parity contract to lock there.

`{$IFDEF FPC}` sets `STRICT_WIDTH` automatically, so the program compiles and
prints `INTTOHEX OK` under FPC 3.2.2 unmodified — the expectations were read off
it, and it stays re-checkable against the oracle.

`make lib-test` green against stable v344.

### Measured: only ONE spelling still widens by default, not four

The 2026-08-14 table in this ticket recorded `Integer`, `SmallInt`, `Byte` and
literal `-1` all resolving to the `Int64` body. Re-measured today against
`pinned` (v344), unflagged, the default-run diff against FPC is **one line**:

| spelling | default dialect | FPC / `--strict-overload-width` |
| --- | --- | --- |
| `Integer` | `FFFFFFFF` ✓ | `FFFFFFFF` |
| literal `-1` | `FFFFFFFF` ✓ | `FFFFFFFF` |
| `SmallInt` | `FFFFFFFFFFFFFFFF` | `FFFFFFFF` |

That looked at first like an inconsistency worth escalating to Track A. It is
not — measured, `SizeOf(Integer) = 4` and `SizeOf(SmallInt) = 2` in this
dialect, so `Integer` is an **exact-width match** for the `LongInt` overload
(nothing to widen) while `SmallInt` is genuinely narrower and widens, which is
precisely the documented default. The rule is coherent as it stands: exact match
wins by default; strictly-narrower spellings widen unless the flag is on. **No
Track A ticket filed.**

The flag was confirmed to be doing real work rather than being silently
accepted: the two binaries differ (`cmp`), and a bogus `--strict-nonsense-flag`
is rejected with `unknown option` — the control that stops "the flag had no
effect" from reading as "the flag fixed it".

Nothing remains in `lib/rtl` for this ticket. Closing.

## Log
- 2026-08-17 — resolved, commit PENDING-COMMIT.

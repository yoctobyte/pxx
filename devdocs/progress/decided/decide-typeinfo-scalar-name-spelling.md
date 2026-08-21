---
track: U
prio: 20
type: decide
blocked-by: []
summary: "TypeInfo(Integer)^.Name: pxx says `Integer`, FPC says `LongInt`. pxx's tyInteger and tyInt32 are separate type kinds where FPC's Integer IS LongInt, so TypeInfoOrdName picks one canonical spelling per pxx kind and Integer keeps its own. Cosmetic today (nothing branches on the string), but it is a visible FPC-parity gap in a compat-sensitive API, and changing it later breaks whatever started reading it."
status: decided
owner: user
---

# U TypeInfo name spelling for scalars: our canonical name, or FPC's?

- **Track U** (decision). Surfaced while widening `TypeInfo(T)`
  (`feature-typeinfo-all-types`); the code is landed and green either way, so
  nothing is blocked on this — it is a parity call worth making before a
  consumer depends on the string.

## The fork

`compiler/rtti_emit.inc`'s `TypeInfoOrdName` maps one canonical spelling per
pxx `TTypeKind`. Measured against FPC 3.2.2:

| source | FPC 3.2.2 | pxx today |
| --- | --- | --- |
| `TypeInfo(Integer)` | `LongInt` | `Integer` |
| `type TMyInt = Integer; TypeInfo(TMyInt)` | `LongInt` | `Integer` |
| `TypeInfo(Byte)` | `Byte` | `Byte` |
| `TypeInfo(Int64)` | `Int64` | `Int64` |

Only the `Integer` row differs, and it differs for a structural reason: in FPC
(objfpc mode) `Integer` is not a type of its own, it is an alias of `LongInt`,
so its typeinfo blob is LongInt's and carries LongInt's name. pxx has `tyInteger`
and `tyInt32` as **separate kinds**, so it has a name of its own to report.

## Options

1. **Keep `Integer`** (today). Honest about pxx's own type system; a user who
   writes `Integer` and reads back `Integer` is not surprised. Diverges from
   FPC on a string an FPC-targeting program could compare.
2. **Report `LongInt`** for `tyInteger`. Byte-for-byte FPC parity on the API.
   Costs: a pxx program that reads back the name it wrote gets a different
   word, and it entrenches an FPC implementation detail (that Integer is
   32-bit and spelled LongInt) into our RTTI.
3. **Make `Integer` a true alias of `tyInt32`** and delete the separate kind.
   The root-cause option — it removes the fork rather than choosing a side —
   but it is a type-system change with reach far past RTTI, so it is a
   different, much larger ticket, not a decision to take here.

## Recommendation

**Option 1, keep `Integer`** — unless a real corpus target is found comparing
the name against `'LongInt'`. Nothing in the repo branches on this string
today; the FPC-parity argument is real but hypothetical, and option 2 buys
parity on the one row by making the other rows describe FPC's type system
rather than ours. Revisit if a compat target actually reads it.

`test/test_typeinfo_named_types.pas` asserts the current answer explicitly and
points here, so whichever way this goes the test is the place to change it.

## ANSWER (user, 2026-08-21) — neither 1 nor 2: BOTH, gated

> *"in strict FPC mode, we just mangle the name 'Integer' to 'Longint'. we are
> already compatible about the underlying type. it's just naming."*

**Keep `Integer` by default; report `LongInt` under strict-FPC mode.** The same
shape as every other parity call made this day: our own answer by default, FPC's
exact convention behind the mimic flag, because *"we seek LANGUAGE compliance,
not error-handling compliance"* — and this is not even semantics, it is a string.

Implementation: [[feature-a-typeinfo-integer-name-under-strict-fpc]].

## Premise corrected before deciding (measured, FPC 3.2.2 / x86-64)

The ticket's table was right but its framing invited two wrong turns, both taken
and both closed by measurement:

| | FPC objfpc/delphi | FPC tp/fpc | pxx x86-64 |
| --- | --- | --- | --- |
| `SizeOf(Integer)` | 4 | **2** | 4 |
| `SizeOf(LongInt)` | 4 | — | 4 |
| `SizeOf(NativeInt)` / `PtrInt` | 8 | — | 8 |
| `TypeInfo(Integer)^.Name` | `LongInt` | — | `Integer` |

- **`Integer` is NOT the native int**, in either compiler. On x86-64 both make it
  4 bytes while native is 8 — Delphi froze it at 32 bits for the 64-bit
  transition and FPC followed.
- **Its width varies by MODE, not by TARGET.** FPC's `Integer` is 16-bit in
  `{$mode tp}` / `{$mode fpc}` and 32-bit in objfpc/delphi. pxx matches the
  objfpc/delphi side and has no 16-bit mode. A "future 16-bit target" argument
  was raised during this discussion and is **withdrawn** — the user's call:
  *"there is no future 16 bit"*, and width is not the axis anyway.
- **pxx and FPC already AGREE on the width.** The whole divergence is the name
  string, exactly as the ticket said.

So option 3 (make `Integer` a true alias of `tyInt32`) buys nothing here — the
observable behaviour is already identical and only the RTTI label differs. It
stays what the ticket called it: a much larger type-system ticket, not this one.

## Why gating beats picking a side

Option 1 alone leaves a real FPC-parity gap in a compat-sensitive API. Option 2
alone buys parity on one row by making every OTHER row describe FPC's type
vocabulary rather than ours — `Integer` genuinely is a distinct kind here
(`tyInteger` vs `tyInt32`), so calling it `LongInt` unconditionally would state
FPC's aliasing as though it were our type system.

Gating gets both and costs two lines, because the underlying type already
matches. That is the cheapest possible resolution and it was not on the ticket's
list.

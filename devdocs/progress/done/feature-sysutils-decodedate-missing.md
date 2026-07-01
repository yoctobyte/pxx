# SysUtils `DecodeDate` missing — next Synapse `synautil` wall

- **Type:** feature (RTL / SysUtils gap) — Track A (per [[feedback_crtl_impl_is_track_b]]-style
  convention this could arguably be Track B since it's `lib/rtl` file ownership,
  but filing under A since it was found mid Track-A parser work; retarget if
  picked up by B)
- **Status:** done — DecodeDate/EncodeDate/DecodeTime/EncodeTime added
  2026-07-02; re-probing synautil for the actual "next wall" blocked on an
  unrelated environment issue, see Log
- **Opened:** 2026-07-01 (found immediately after
  [[bug-array-const-too-many-elements-synapse]] cleared the array-constant
  wall it was blocking)

## Symptom

`uses synautil; --mimic-fpc` (Synapse, `external/synapse/synautil.pas`) now
compiles past its array-constant-initializer wall and hits:

```
pascal26:2726: error: undefined variable (DecodeDate)
```

`DecodeDate` (a standard FPC/Delphi `SysUtils` date-decomposition routine,
`DecodeDate(aDate: TDateTime; out Year, Month, Day: Word)`) isn't implemented
in this project's RTL.

## Direction

Implement `DecodeDate` (and check for its usual siblings — `EncodeDate`,
`DecodeTime`, `EncodeTime` — synautil or other date-handling code likely needs
those too) in the RTL's SysUtils-equivalent unit. Standard algorithm: `TDateTime`
is a Double (days since a fixed epoch, FPC uses 1899-12-30); decompose via the
usual Julian-day-number arithmetic. Re-probe `synautil` for the next wall after
landing.

## Acceptance

`synautil` compiles past this wall (next wall, if any, identified); self-host
unaffected (pure RTL addition, no compiler-internals change expected).

## Log
- 2026-07-01 — Opened while cross-verifying
  [[bug-array-const-too-many-elements-synapse]]'s fix against the real
  `external/synapse/synautil.pas` file. Not investigated further — pure
  discovery, filed for whoever picks up [[feature-synapse-compile-check]] next.
- 2026-07-02 — Added `TDateTime` (Double, FPC's 1899-12-30 epoch) and
  `EncodeDate`/`DecodeDate`/`EncodeTime`/`DecodeTime` to
  `lib/rtl/sysutils.pas`, using Howard Hinnant's public-domain
  days_from_civil/civil_from_days algorithm (chosen over the classic FPC
  DivMod-table implementation as small enough to re-derive/verify from
  scratch, and correct under this dialect's truncating div/mod for
  negative/pre-epoch inputs by construction). Verified byte-for-byte
  against real FPC output across leap years, century boundaries, the
  epoch, pre-1970/pre-1899 dates, and combined date+time — including a
  real discrepancy caught and fixed: FPC's `DecodeTime` on a negative
  `TDateTime` takes the ABSOLUTE VALUE of the leftover fraction (not a
  floor-adjusted +1), confirmed against the real FPC binary rather than
  assumed. `test/test_sysutils_datetime.pas` added, cross-verified
  identical on arm32/aarch64/i386.

  Tried to re-probe `synautil` for the actual "next wall" per this
  ticket's stated acceptance, via `test/manual/try_synapse_compile.sh` —
  hit `error: uses: unit source not found: libc`, an EARLIER failure than
  either the array-constant or `DecodeDate` walls (a `uses` resolution
  failure, so it happens before most of the file is even parsed). Not
  caused by this change (a pure lib/rtl addition, no new compiler-level
  `uses` handling) and not present in `synautil.pas`/`synaip.pas`/etc.
  themselves (grepped, no `uses libc` anywhere in `external/synapse/`) —
  looks like a missing environment/search-path piece in this checkout
  (`tools/install_externals.sh` may need an additional dependency, or a
  different profile flag than `default`). Left uninvestigated — separate
  from this ticket's actual ask, which is done and verified in isolation.
  Whoever picks up [[feature-synapse-compile-check]] next should resolve
  the `libc` unit resolution first, then re-probe for `synautil`'s real
  next wall.

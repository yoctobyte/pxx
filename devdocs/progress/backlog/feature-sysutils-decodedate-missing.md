# SysUtils `DecodeDate` missing — next Synapse `synautil` wall

- **Type:** feature (RTL / SysUtils gap) — Track A (per [[feedback_crtl_impl_is_track_b]]-style
  convention this could arguably be Track B since it's `lib/rtl` file ownership,
  but filing under A since it was found mid Track-A parser work; retarget if
  picked up by B)
- **Status:** backlog
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

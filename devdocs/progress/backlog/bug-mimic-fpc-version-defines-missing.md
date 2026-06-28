# Bug: `--mimic-fpc` missing FPC version integer defines (`FPC_VERSION`, `FPC_RELEASE`, `FPC_FULLVERSION`)

- **Type:** bug
- **Track:** A
- **Status:** backlog
- **Opened:** 2026-06-28
- **Found-by:** Pascal Script v83 compile probe (Track B)

## Symptom

Under `--mimic-fpc`, `{$IF DEFINED(FPC) and (FPC_VERSION >= 3)}` fails with:

```
pascal26:0: error: conditional directive: comparison requires integer operands ()
```

## Minimal repro

```pascal
program p;
{$IF DEFINED(FPC) and (FPC_VERSION >= 3)}
var x: integer;
{$ENDIF}
begin end.
```

## Root cause

`--mimic-fpc` defines `FPC` (the symbol) but does not define `FPC_VERSION`,
`FPC_RELEASE`, `FPC_PATCH`, or `FPC_FULLVERSION` as integer constants. Real FPC
3.2.2 defines:

```
FPC_VERSION    = 3
FPC_RELEASE    = 2
FPC_PATCH      = 2
FPC_FULLVERSION = 30202
```

Without these, `{$IF (FPC_VERSION >= 3)}` hits an undefined identifier, which
the `{$IF}` evaluator cannot compare as an integer.

## Impact

Blocks `uPSRuntime.pas` in the Pascal Script compile probe — `x64.inc` / `arm64.inc`
use `{$IF DEFINED(FPC) and (FPC_VERSION >= 3)}` for calling convention stubs.
Also likely blocks any real-world FPC library that version-guards code this way.

## Fix

Add `FPC_VERSION = 3`, `FPC_RELEASE = 2`, `FPC_PATCH = 2`, `FPC_FULLVERSION = 30202`
as predefined integer constants under `--mimic-fpc` (matching the FPC 3.2.2 target
the mimic profile was designed for).

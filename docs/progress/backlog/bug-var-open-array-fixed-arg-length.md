# `var`/`out` open-array param: fixed-array argument passes a wrong length

- **Type:** bug (codegen / open-array ABI)
- **Status:** backlog
- **Owner:** — (Track A)
- **Opened:** 2026-06-22
- **Found-by:** Synapse recon (`synacode.pas` `ArrByteToLong(var ArByte: array of
  byte; var ArLong: array of Integer)`). Independent of the capital-`array`
  keyword fix (b5c0252) that first unblocked that line.

## Symptom

Passing a **fixed** array to a **`var` (or `out`) open-array** parameter passes
the data pointer correctly but the implicit high/length is wrong (`High(a)` =
**-1**, i.e. length 0). The element data is reachable (`a[0]` reads correctly),
so only the length companion is broken.

- `value` open-array param (no `var`): **works** (correct High).
- `var` open-array param, **dynamic-array** argument: **works** (the dyn handle
  carries its own length).
- `var` open-array param, **fixed-array** argument: **BROKEN** — High = -1.
- Element type irrelevant (Byte and Integer both fail).

## Minimal repro

```pascal
program p;
procedure S(var a: array of Integer; var h: Integer);
begin h := High(a); end;
var f: array[0..2] of Integer; h: Integer;
begin S(f, h); WriteLn(h); end.   { prints -1; expected 2 }
```

`x := a[0]` in the same shape returns the right element, so the data pointer is
fine; only the length is lost.

## Likely cause

An open-array parameter is a fat argument (data pointer + high). For a `value`
open-array the caller materialises both correctly; for a **`var`** open-array
the by-reference path appears to pass the data address but drop / zero the
implicit high when the source is a fixed array (a dynamic source recovers it
from its handle, which is why dyn works). Look at the call-site open-array
marshalling for `pbyref[i] and parr[i]` (param loop ~parser.inc 9817/9842 sets
`parr`/`pbyref`) and how the High companion is computed for a fixed-array
lvalue argument vs a dynamic one. Compare the working value-param path.

## Why it matters

Blocks any FPC/Synapse routine taking `var X: array of T` and calling
`Length`/`High` on it — `synacode.ArrByteToLong` is the concrete case, so this
is on the Synapse compile path ([[feature-synapse-compile-check]]).

## Gate

`make test` (self-host byte-identical) + `make cross-bootstrap`. Add a test
(extend `test/test_keyword_array_case.pas` or a new one) covering fixed-array →
`var array of T` High/Length once fixed.

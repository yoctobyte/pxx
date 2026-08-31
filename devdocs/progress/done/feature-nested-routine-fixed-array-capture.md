---
prio: 50
owner: frankA
---

# Nested routines: capture of fixed-size array locals not supported

- **Type:** feature gap (frontend/codegen — nested-routine uplevel access) — **Track A**
- **Status:** done
- **Opened:** 2026-07-11, filed from Track B (feature-dns-resolver-library) while
  writing `DnsParseIpv6` in `lib/rtl/dns_config.pas`.

## Symptom

A nested routine that reads or writes a fixed-size array local of its enclosing
routine fails to compile:

```
pascal26:144: error: nested routine: capture of fixed-size array 'rightG' not yet supported ()
```

Repro shape (rejected):

```pascal
function Outer: Boolean;
var
  leftG, rightG: array[0..7] of Integer;
  leftN, rightN: Integer;
  onRight: Boolean;

  function AddGroup(v: Integer): Boolean;
  begin
    AddGroup := False;
    if leftN + rightN >= 8 then Exit;
    if onRight then begin rightG[rightN] := v; rightN := rightN + 1; end
    else begin leftG[leftN] := v; leftN := leftN + 1; end;
    AddGroup := True;
  end;

begin
  ...
end;
```

Scalar captures (`leftN`, `onRight`) work; the fixed-size array locals are the
missing case. FPC accepts this.

## Workaround used

Flattened the helper into the enclosing routine (single `g[0..7]` array +
index bookkeeping inline) — see `DnsParseIpv6` in `lib/rtl/dns_config.pas`.

## Acceptance

- Nested routine can read and write a fixed-size array local (and array
  parameter) of any enclosing routine, at any nesting depth.
- Works for element access, whole-array passing to further calls, and
  `for`-loop iteration over the captured array.
- Self-host stays byte-identical; a compile-run test in the nested-routines
  test family covers array capture.

## Implemented 2026-08-31 (frankA) — 1-D fixed arrays; multi-dim still refused

`50fcbddef`. Nested routines lift: the routine becomes top-level and each
captured local becomes a by-reference parameter. A dynamic array is
self-describing at runtime; a fixed one carries its extent only in its **type**,
and the enclosing `Syms` slot is recycled before the lifted body is parsed — so
the shape has to be snapshotted at capture rather than read later.

**Measured first, and that is what made it plumbing rather than a feature.** A
named-fixed-array `var` parameter already works end to end, and `ParseSubroutine`
already replays a shape onto one via `pFixedLen`/`pFixedLo`. Nothing new was
taught to the backend; the capture path simply refused and dropped the two
numbers.

| | |
| --- | --- |
| capture (`pasparser_decl.inc`) | snapshot `ArrLen` and the low bound |
| carry (`defs.inc`) | `LiftCapFixedLen` / `LiftCapFixedLo` |
| lift (`pasparser_proc.inc`) | replay onto `pFixedLen` / `pFixedLo` |

The **low bound** is the half that fails silently — without it `IR_INDEX`
subtracts 0 and `g[1]` of an `array[1..3]` writes the next element. It is row 1
of the test for that reason.

### Acceptance, item by item

- read and write a fixed array local of an enclosing routine — **yes**
- at any nesting depth — **yes**, tested two levels up
- whole-array passing to further calls — **yes**
- `for`-loop iteration over the captured array — **yes**
- self-host byte-identical — **yes**, see the control below
- a compile-run test in the nested-routines family — `test/test_nested_fixed_array_capture.pas`, wired into `test-core`

### NOT done, and named in the diagnostic rather than left to be rediscovered

Multi-dimensional arrays still refuse, now with
`capture of multi-dimensional array 'm' not yet supported (1-D fixed arrays are)`.
They need the per-dim lo/span vectors carried as well, which is wider than the
use case this was filed from. **Array *parameters* of an enclosing routine were
in the acceptance text and are not separately tested** — the capture arm keys off
`Syms[].IsArray` for `skLocal` and `skParam` alike, so it should follow, but
"should" is not a measurement and this row is honestly open.

### Controls

The test **fails on the pre-change compiler** with the original error — checked,
because a test written after the fix that passes on the old binary is testing
nothing. And the change is provably additive: same sources through both
compilers give a **byte-identical ELF** for 8 programs, including
`test_nested_dynarray`, `test_nested_dynarray_managed`,
`test_nested_dynarray_setlen` and `test_nested_alias` — which exercise the very
capture path this edits — plus a NilPy nested-capture canary, since `defs.inc` is
shared across frontends.

`gate.sh quick` GREEN; fixedpoint converged, 1 round, `ee45a08cbc7f`.

**Track B follow-up available:** `DnsParseIpv6` in `lib/rtl/dns_config.pas` was
flattened by hand to work around this and can now be written the intended way.
Not done here — that is B's file and B's gate.


## Log
- 2026-08-31 — resolved, commit 6bc2d8c5c.

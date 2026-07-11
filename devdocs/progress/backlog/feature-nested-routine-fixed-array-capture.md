---
prio: 35
---

# Nested routines: capture of fixed-size array locals not supported

- **Type:** feature gap (frontend/codegen — nested-routine uplevel access) — **Track A**
- **Status:** backlog
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

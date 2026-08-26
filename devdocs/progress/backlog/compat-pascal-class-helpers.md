---
summary: "pxx rejects FPC's `class helper for T` at parse time — `TFooHelper = class helper for TFoo` is `error: unexpected token`"
type: compat
track: P
prio: 58
---

# `class helper for` is not parsed

- **Type:** compat (Pascal frontend parity) — Track P
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh`, class-helper case batch. The three
  cases are tagged `[known]` there and will start reporting the moment the
  syntax parses, so the semantics below are already under test.

## Repro

```pascal
program h;
type
  TBox = class
    Value: Integer;
  end;
  TBoxHelper = class helper for TBox
    function Doubled: Integer;
  end;
function TBoxHelper.Doubled: Integer; begin Result := Value * 2; end;
var b: TBox;
begin
  b := TBox.Create; b.Value := 21; writeln(b.Doubled); b.Free;
end.
```

FPC (`-Mobjfpc`) prints `42`. pxx: `error: unexpected token`.

## The semantics, if it is implemented

The probe pins the two that are easy to get wrong:

- **A helper method shadows an inherited *virtual* method non-virtually.** With
  `TBase.Name` virtual returning `'base'` and `TBaseHelper.Name` returning
  `'helper'`, FPC prints `helper` for **both** `o.Name` and `TBase(o).Name` —
  the helper wins at every static type that sees it, and the virtual dispatch
  never runs.
- **An unqualified name inside a helper method binds to the extended type's
  members.** `TThingHelper.Tag2` calling bare `Tag` reaches `TThing.Tag`.

Only one helper is active for a given type at a point in the source (the
last one in scope wins); the probe deliberately does not test that yet.

## Scope note

Related but distinct, and not covered here: `type helper for Integer` (record /
type helpers), which FPC gates behind `{$modeswitch typehelpers}`. Worth a
separate ticket — the parse work overlaps, the binding rules do not.

## Gate

Track P: `make test` + self-host fixedpoint (byte-identical). Note the Track P
catch — the Pascal frontend lives in the shared `lexer.inc`/`parser.inc`, so
this must not be edited concurrently with Track A.

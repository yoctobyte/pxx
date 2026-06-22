# `@Proc` / proc-value of a `procedure`-typed routine rejected ("unexpected token")

- **Type:** bug (compiler / parser) — **Track A**
- **Status:** backlog
- **Severity:** MEDIUM — blocks procedure-typed callbacks (event handlers, the
  common `procedure(Sender: TObject)` shape); `function`-typed proc values work.
- **Opened:** 2026-06-22
- **Owner:** — (Track A)
- **Found by:** Track A, while testing `{$mode delphi}` (independent of it —
  reproduces on the pinned v37 and default mode too).

## Symptom

A proc value whose target type is a **`procedure`** (no return) is rejected:

```pascal
type TProc = procedure(x: Integer);
var p: TProc;
procedure Hello(x: Integer); begin writeln(x); end;
begin
  p := @Hello;     { pascal26: error: unexpected token () }
  p(5);
end.
```

The identical shape with a **`function`** type compiles and runs:

```pascal
type TFn = function(x: Integer): Integer;
var p: TFn;
function Dbl(x: Integer): Integer; begin Dbl := x*2; end;
begin
  p := @Dbl;       { OK }
  writeln(p(5));   { 10 }
end.
```

## Scope

- Reproduces on **pinned v37** (pre-`{$mode delphi}`) and on `master` HEAD, in
  the **default** mode — so it is a pre-existing proc-type gap, NOT a mode-delphi
  regression. Surfaced only because the mode-delphi `@`-relax test happened to use
  a `procedure` type first.
- `function`-typed proc vars (`SymProcSig` set, `@Fn`, indirect call) all work
  ([[project_procedural_types_arc]]).
- The error is at parse time on the `p := @Hello` line ("unexpected token"),
  pointing at the `procedure`-typed declaration or the `@`-of-a-procedure path —
  likely the proc-TYPE parse (`= procedure(...)` with no result) not setting the
  same `SymProcSig`/signature state a `function(...)` type does, so the `@Proc`
  bind mis-parses.

## Suggested next steps

1. Diff how `type T = function(...): R` vs `type T = procedure(...)` register
   their signature (`ProcSig`/`SymProcSig`, param table) — the procedure form is
   probably missing a piece the `@`/assign path relies on.
2. Minimal repro is the block above; add a `procedure`-typed proc-var test
   alongside the existing function-typed one once fixed.

## Log
- 2026-06-22 — filed (Track A) from mode-delphi testing. Pre-existing; reproduces
  on v37 + default mode. `function`-typed proc values are unaffected.

# `@Proc` / proc-value of a `procedure`-typed routine rejected ("unexpected token")

- **Type:** bug (compiler / parser) — **Track A**
- **Status:** done
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

## Resolution (2026-06-22, Track A, commit `e130d07`)

**Reframed — NOT a @procedure / proc-value bug.** Procedure-typed proc values
work fine (a non-colliding type name like `TMyProc` always compiled + called).
The real cause was a **name collision**: the test type was named `TProc`, which
the compiler reserves for an internal descriptor record (`REC_TPROC`, exposed for
self-reflection). Type-name resolution checked the builtin record
(`IsRecordType`) BEFORE the user alias (`FindTypeAlias`), so `var p: TProc`
resolved to the builtin record (`tyRecord`), the proc var lost its signature, and
the indirect call `p(x)` fell through to "unexpected token".

**Fix:** a user `type X = ...` alias now shadows a same-named builtin record
(skip the builtin when a user alias of that name exists). FPC doesn't reserve
these names. Only triggers on the user-alias-vs-builtin overlap; `compiler.pas`
defines no such alias, so the builtins still resolve there -> self-host
byte-identical, cross-bootstrap byte-identical. Test
`test/test_user_type_shadows_builtin.pas` (matches FPC). Retires the "TProc-name
collision landmine".

## Log
- 2026-06-22 — filed (Track A) from mode-delphi testing.
- 2026-06-22 — DONE. Root cause = user-alias-vs-builtin-record name collision
  (TProc), not proc-value handling. Fixed in type-name resolution (`e130d07`).

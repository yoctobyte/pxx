# Text-file primitives (`Assign`/`Rewrite`/`Reset`/`Close`) not visible inside a unit

- **Type:** bug (name resolution / RTL ambient scope)
- **Track:** A — `compiler/**` (or RTL surfacing)
- **Status:** backlog (filed by Track B)
- **Owner:** — (Track A)
- **Opened:** 2026-06-25
- **Found-by:** [[feature-demo-mandelbrot]] discovery loop → `make demos` shows
  `examples/adventure/adventure.pas` FAIL: `pascal26:652: error: undefined
  variable (Assign)`. This is adventure's predicted **F1** (text file I/O) — but
  F1 is actually *implemented* now; the gap is that it is not visible from a unit.

## Symptom

The classic Text-file procedures (`Assign`, `AssignFile`, `Reset`, `Rewrite`,
`Append`, `Close`, `writeln(f,…)`) are ambient inside a **program** but
**undefined inside a unit** — even one that `uses sysutils`.

| context | `uses` | sees `Assign`? |
| --- | --- | --- |
| program | (none) | yes — compiler auto-injects the primitives |
| program | sysutils | yes |
| **unit** | sysutils | **no — `undefined variable (Assign)`** |
| unit | sysutils | `IntToStr` etc. visible; only the file procs are missing |
| unit | textfile (explicit) | yes |

The `Text` *type* itself resolves in a unit (a bare `var f: Text` compiles); only
the file *procedures* are missing. So whatever step makes `lib/rtl/textfile`'s
procedures ambient runs for a program's main scope but not for a unit's
interface/implementation scope.

### Minimal repro

```pascal
unit eng;
interface
uses sysutils;
procedure P;
implementation
procedure P;
var f: Text;
begin
  Assign(f, '/tmp/u.txt'); Rewrite(f); Close(f);   { error: undefined variable (Assign) }
end;
end.
```

`uses sysutils, textfile;` (explicitly naming `textfile`) compiles and runs.
Note `sysutils` does **not** `uses textfile` (it uses `platform, platform_types`)
— so the program-scope visibility comes from a compiler auto-injection, not from
sysutils re-exporting.

## Impact

Any **unit** that does file I/O the FPC way (no `uses textfile`, because in FPC
`Assign`/`Reset`/`Rewrite`/`Close` live in `System` and are ambient everywhere)
fails to compile. This is the adventure engine's blocker and will hit every
library/demo unit that reads or writes a file. Idiomatic FPC code never names a
`textfile` unit, so requiring it is non-platonic.

## Fix

Make the `textfile` primitives ambient in **unit** scope exactly as they already
are in **program** scope (mirror FPC: these are System-unit routines available
to programs and units alike). Whatever injects them into the program's global
scope should also inject them when compiling a unit.

## Done when

- The minimal-repro unit above compiles with only `uses sysutils` (or no uses).
- `examples/adventure/adventure.pas` advances past the `Assign` error (its next
  predicted failure, not this one).
- Regression test under `make test`; self-host fixedpoint byte-identical.

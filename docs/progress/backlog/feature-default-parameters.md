# feature: default parameter values

- **Type:** feature (Track A — parser + call lowering)
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** medium (common FPC/Delphi idiom; forces overloads or explicit args)

## Gap

A parameter with a default value is rejected at parse:

```pascal
function f(a: integer; b: integer = 10): integer; begin f := a + b; end;
begin writeln(f(5), '|', f(5, 1)); end.
{ fpc: 15|6    pxx: error: unexpected token  (at '=') }
```

## Expected

Accept `param: type = constexpr` in a routine signature; a call that omits the
argument supplies the default (`f(5)` → `a=5, b=10`). Defaults must be trailing
and constant-foldable (FPC rules).

## Track B impact

Library APIs must either overload or require all arguments. Low-risk to live
without, but it is a routine convenience used throughout idiomatic Pascal.

## Repro

`tools/fpc_diff_probe.sh` (`default-param`).

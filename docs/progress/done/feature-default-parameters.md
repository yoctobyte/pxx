# feature: default parameter values

- **Type:** feature (Track A — parser + call lowering)
- **Status:** done
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

## Resolution (2026-06-23)

Default values for trailing parameters, constant-folded (ordinal/char/bool/enum):

- Parser: a `: type = constexpr` after a param is parsed (ConstEval) into
  per-param `pdefault`/`pdefaultval`, threaded to new `ProcParamHasDefault` /
  `ProcParamDefaultVal` storage at proc registration.
- Overload: `ProcArityMatches(i, nArgs)` accepts a call that omits trailing args
  whose params all carry a default (exact arity unchanged for everything else);
  wired through MatchProcCall's exact/compatible/interface phases.
- Call lowering (ir.inc AN_CALL): after the supplied args, omitted trailing
  params are filled with their default via IR_CONST_INT.

f(5)=15, f(5,1)=6; multi/partial defaults g(1)/g(1,20)/g(1,20,300)=103/121/321;
Boolean default p(7)/p(8,false). Byte-identical self-host (inert for exact-arity
calls; no existing code uses defaults). Limitation: ordinal-foldable defaults
only (string/float defaults not yet). Gate: full make test (ir + overload reach).
Closes feature-default-parameters.

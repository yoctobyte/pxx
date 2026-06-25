# Indexed / element proc-value call: `arr[i](args)`

- **Type:** feature (Track A — parser + element proc-sig tracking)
- **Track:** A — `compiler/**`
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-25
- **Split-from:** [[bug-proc-typed-call-const-record-arg]] (its array-element
  symptom; the scalar/const-record half is fixed).
- **Found-by:** [[feature-demo-chess]] — `Evaluate` calls eval terms through a
  procedural-typed table `EvalTerms[i](pos)`.

## Symptom

Calling a proc-typed value held in an ARRAY ELEMENT is not parsed as an indirect
call at all:

```pascal
type TFn = function(x: Integer): Integer;
function Dbl(x: Integer): Integer; begin Dbl := x*2; end;
var arr: array[0..0] of TFn;
begin arr[0] := @Dbl; writeln(arr[0](21)); end.   { error: unexpected token () }
```

A scalar proc var (`fn(args)`) and a record FIELD proc value (`rec.fn(args)`,
via `UFldProcSig`) both work; only the array-element form is missing.

## Why

`ParseProcVarCallAST` and its callers only special-case a *simple identifier*
callee (fires when `(` immediately follows the name). For `arr[i]` the callee is
an `AN_INDEX`, and the array's **element proc signature is not tracked** (there is
`SymProcSig` for a var and `UFldProcSig` for a field, but no element equivalent),
so the postfix `(args)` after an indexed proc value has nowhere to bind. `arr[0]`
yields the pointer and the `(...)` is dropped / mis-parsed.

## Fix sketch

1. Record an element proc signature for `array of <proctype>` — a new
   `SymElemProcSig` (mirroring `UFldProcSig`), captured from `LastTypeProcSig` at
   the array declaration. NB: every symtab `Alloc*` must reset it to -1 (the
   parallel-array landmine), and that reseeds once.
2. In the ParseFactor postfix loop, after building an `AN_INDEX` whose base array
   has an element proc sig and `(` follows, build `AN_CALL_IND` (mirror the field
   path at parser.inc ~1882), method-pointer flag when the element is `of object`.

## Done when

- `arr[i](args)` (and `EvalTerms[i](pos)` with a `const record` param) compiles and
  calls correctly; the chess eval no longer saturates to ±INF.
- Regression test under `make test`; self-host fixedpoint byte-identical.

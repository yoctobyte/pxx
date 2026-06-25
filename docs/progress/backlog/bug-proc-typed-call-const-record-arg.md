# bug: indirect call through a proc-typed value with a `const record` arg miscompiles

- **Type:** bug (Track A — codegen, indirect/procedural call ABI)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-25
- **Found-by:** [[feature-demo-chess]] — `Evaluate` calls eval terms through a
  procedural-typed table `EvalTerms[i](pos)` where `pos: const TPosition`. Every
  table call returned a code address instead of the term value, so the whole
  search saturated to `±INF` (startpos "score 30000"); the **perft oracle is
  unaffected** (it makes no eval calls).

## Symptom

Calling a procedural-typed **value** (function pointer — scalar var *or* array
element) whose signature has a **`const <record>`** parameter passes the arg
wrong: scalar form **segfaults**, array-element form returns a **garbage / code
address**. The same function called **directly** is correct, and indirect calls
are correct when the param is a **value record** or a scalar (`Integer`).

```pascal
program pt;
type TRec = record a, b: Integer; end;
     TFn  = function(const r: TRec): Integer;
function Sum(const r: TRec): Integer;
begin Sum := r.a + r.b; end;
var fn: TFn; arr: array[0..0] of TFn; r: TRec; viaArr: Integer;
begin
  r.a := 30; r.b := 12;
  writeln(Sum(r));            { 42  — direct, correct }
  fn := @Sum;
  writeln(fn(r));             { SEGFAULT — indirect scalar, const record }
  arr[0] := @Sum;
  viaArr := arr[0](r);
  writeln(viaArr);            { 4225743 (a code address) — indirect array }
end.
```

## Narrowing (minimal, x86-64 / v66 stable)

| call form | param kind | result |
| --- | --- | --- |
| `Sum(r)` direct | `const TRec` | **42 (OK)** |
| `fn(r)` scalar proc-typed | `const TRec` | **segfault** |
| `arr[0](r)` array proc-typed | `const TRec` | **garbage (code addr)** |
| `fn(r)` scalar proc-typed | `TRec` (by value) | 42 (OK) |
| `fn(21)` scalar proc-typed | `Integer` | 42 (OK) |

So the broken axis is **indirect call + `const record` parameter**. The garbage
values are increasing code-segment addresses (`@Sum` itself / adjacent function
entries), i.e. the const-record arg lowering on the indirect path is wrong — the
callee reads the function pointer / a bad address instead of the record's
address.

## Likely cause

Const-record args are passed **by hidden reference** (address of the record). The
**direct**-call path lowers that address correctly; the **indirect** (proc-typed
value) path appears to lower the const-record arg differently — probably failing
to take the address (passing the record by value into a slot the callee derefs as
a pointer, or clobbering the arg register with the call target). Compare the
arg-setup for `AN_CALL` (direct) vs the indirect/proc-value call path for a
`const`-by-ref aggregate parameter.

## Secondary (separate, minor) parser quirk

`arr[i](args)` used as a **sub-expression** of another expression (e.g. directly
inside a `writeln(...)` argument list) fails to parse: `error: unexpected token
()`. Assigning to a temp first (`v := arr[i](args)`) parses fine, and the same
call inside a plain `s := s + arr[i](x)` assignment parses. Worth a glance but
independent of the codegen bug above.

## Acceptance

- `fn(r)` / `arr[i](r)` through a proc-typed value with a `const record` param
  returns the same value as the direct call, on all targets; no segfault.
- Regression test (proc-typed table of `function(const rec): Integer`).
- Unblocks [[feature-demo-chess]] slice 2 (search + eval): `Evaluate`'s
  proc-typed term table yields correct scores (startpos ≈ 0, not ±INF).

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
| `fn(r)` scalar proc-typed | **`var TRec`** (by ref) | **42 (OK)** |
| `fn(100, r)` scalar proc-typed | `Integer; const TRec` | **segfault** |

So the broken axis is precisely **indirect call + a `const record` parameter** —
**`var record` (also by-reference) is fine**, and the break persists when the
const-record is not the first arg. That isolates it to how a `const` aggregate
arg (as opposed to `var`) is lowered on the indirect/proc-value call path. The
garbage
values are increasing code-segment addresses (`@Sum` itself / adjacent function
entries), i.e. the const-record arg lowering on the indirect path is wrong — the
callee reads the function pointer / a bad address instead of the record's
address.

## Likely cause

Both `const` and `var` record args are passed **by hidden reference** (address of
the record), yet on the indirect path **`var` works and `const` does not** — so
the two are lowered by different code, and only the `const`-aggregate branch is
wrong on the proc-value path (it likely fails to take the record's address —
passing it by value / a bad pointer the callee then derefs, or clobbering the arg
register with the call target). The **direct**-call path lowers `const` records
correctly. Compare arg-setup for `AN_CALL` (direct) vs the indirect/proc-value
call path, specifically the `const`-aggregate-by-ref branch against the (working)
`var`-aggregate branch.

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

## Resolution (2026-06-25, Track A)

Scalar form FIXED (67c5536): the proc-TYPE mini-parser consumed `const` but never
marked the param by-reference, while a real routine forces const record/variant
params by-ref (ParseSubroutine ~11403). The signature's IsRef therefore disagreed
with the callee → the indirect call passed a value where the callee expected an
address → segfault. Applied the same const-record/variant -> by-ref rule in the
proc-type parser; signature and callee now agree. Test:
test/test_proc_const_record.pas (42 / 42). Self-host byte-identical; make test green.

The ARRAY-ELEMENT symptom in this ticket was a DIFFERENT root cause — indexed
proc-value calls (`arr[i](args)`) are not parsed at all (it errors even with an
int arg, no const record involved). Split to [[feature-indexed-proc-value-call]].

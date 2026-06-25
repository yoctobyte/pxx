# bug: function Result of a managed-field record, passed as a call arg in its own reassignment, segfaults

- **Type:** bug (codegen — managed-record return value / hidden result pointer aliasing)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-25
- **Found-by:** Track B, building `lib/rtl/chacha20poly1305.pas` — a Poly1305
  accumulator over `bignum` (`Result := BigAdd(BigMulSmall(Result,256), …)`)
  crashed; reduced to the managed-record return pattern below. Worked around in
  that unit by accumulating in a local, but the bug is general.

## Symptom

A function whose return type is a **record with a managed field** (here a dynamic
array; an AnsiString field is the same shape), where the function's **`Result`**
is passed as an **argument** to a call whose value is assigned **back to
`Result`**, segfaults. Routing through a local accumulator instead works.

```pascal
program mr;
type TR = record d: array of Integer; end;
function Make(n: Integer): TR;
begin SetLength(Result.d, 1); Result.d[0] := n; end;
function Add(const a, b: TR): TR;
begin SetLength(Result.d, 1); Result.d[0] := a.d[0] + b.d[0]; end;

function ViaResult: TR;        { Result is a call arg in its own reassignment }
begin
  Result := Make(10);
  Result := Add(Result, Make(5));    { SEGFAULT }
end;

function ViaLocal: TR;         { same logic via a local }
var acc: TR;
begin
  acc := Make(10);
  acc := Add(acc, Make(5));
  Result := acc;                      { OK -> 15 }
end;
```

`ViaLocal` prints 15; `ViaResult` cores (SIGSEGV), x86-64 / stable v68.

## Likely cause

`Add(Result, …)` is lowered with the callee's hidden return-slot pointer aliasing
`Result` (the same storage is both an input arg and the destination). When the
callee builds its managed result and the caller then assigns it onto `Result`,
the old `Result.d` is released/overwritten while still referenced as the `const a`
argument — a use-after-free / double-manage of the dynamic-array (or string)
field. A plain (unmanaged) record, or a non-`Result` destination, dodges it.

Compare against the value-record / `var`-record arg paths (those are fine) and the
managed-string-field family ([[bug-setlength-record-field-via-var-param]] fixed
v67, [[bug-managed-length-via-pointer-deref]]) — this is the return-slot/self-arg
corner of the same managed-aggregate area.

## Acceptance

- `Result := F(Result, …)` for a managed-field record returns the right value on
  all targets; no segfault (materialise the call result into a temp before
  releasing/overwriting `Result`, or stop aliasing the result slot with an arg).
- Regression test (record-with-dynamic-array and record-with-AnsiString).

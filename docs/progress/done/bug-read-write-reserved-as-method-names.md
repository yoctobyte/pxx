# `Read` / `Write` can't be used as method names (reserved)

- **Type:** bug (lexer/parser) — language
- **Status:** urgent (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** Classes / TStream ([[feature-own-net-http-lib]]) — `TStream.Read` /
  `TStream.Write`.

## Symptom

Declaring a method named `Read` or `Write` fails, even with ordinary typed
parameters:

```pascal
type TC = class
  function Read(p: Pointer; Count: Integer): Integer;   { ERROR }
  function Write(p: Pointer; Count: Integer): Integer;
end;
```
→ `error: expected method name` at the `Read` line.

`Read`/`Write` are lexed as reserved tokens (for the `Read`/`Readln`/`Write`/
`Writeln` console/file intrinsics) and so are not accepted as identifiers in a
method-name position.

## Impact

`TStream.Read` / `TStream.Write` are the canonical FPC/Delphi stream method names
— synapse and all stream code call `stream.Read(buf, n)` / `stream.Write(buf,
n)`. Without these names the standard `TStream`/`TMemoryStream` cannot be
expressed (renaming them breaks compatibility). Together with
[[bug-untyped-params-in-methods]] this blocks the stream surface.

## Fix

`Read`/`Write` (and `Readln`/`Writeln`) are intrinsics resolved at the **call
site by context**, not true reserved words — allow them as identifiers in a
declaration/member-name position (method names, and ideally fields/locals). FPC
treats them as system identifiers that user declarations can shadow. The call
`stream.Read(...)` already has a receiver, so it should resolve to the method,
not the console intrinsic.

## Done when

- A class may declare `Read`/`Write` methods; `obj.Read(...)` calls the method
  while bare `Read(...)`/`Write(...)` still reach the console/file intrinsics.
- `TStream`/`TMemoryStream` compile (with [[bug-untyped-params-in-methods]]).
- Regression test under `make test`; self-host fixedpoint byte-identical.

## Log
- 2026-06-24 — FIXED (Track A). Read/Write/Readln/Writeln carry their text in SVal,
  so they are accepted as method NAMES via a new `IsMemberNameTok` helper at the
  method-declaration and implementation-header name positions (parser.inc). Member
  CALL sites (`stream.Read(...)`) already accepted them. Verified: a class with
  virtual `Read`/`Write` declares, implements, and dispatches.
  RESIDUAL (separate, filed bug-virtual-keyword-name-result): assigning such a
  method's result by its OWN name (`Read := x`) inside a VIRTUAL method
  miscompiled the return value; that form is now a clear compile error directing
  to `Result := ...` (which is correct in all cases) instead of silently
  mis-storing. Regression test/test_stream_methods.pas in make test.

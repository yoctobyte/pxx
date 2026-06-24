# PChar → string implicit conversion missing in call args (and assignment helper)

- **Type:** bug (parser/overload resolution + RTL helper wiring)
- **Status:** backlog (Track A)
- **Owner:** — (**Track A** — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** [[feature-synapse-compile-check]] — Synapse's `SynaFpc` calls
  `dynlibs.LoadLibrary(ModuleName)` with `ModuleName: PChar` against a
  `string`-param routine; FPC auto-converts, PXX rejects.

## Symptom

FPC implicitly converts `PChar` to `string`/`AnsiString` when passing an
argument or assigning. PXX does not:

```pascal
function f(const s: string): Integer; begin Result := Length(s); end;
var pc: PChar;
begin pc := 'abc'; writeln(f(pc)); end.
```
→ `Mismatch in MatchProcCall: name = f, nArgs = 1` (overload resolution does not
consider PChar assignable to a string parameter).

Plain assignment is half-wired — it *tries* to convert but the helper is not
found in a minimal program:

```pascal
var s: string; pc: PChar;
begin pc := 'abc'; s := pc; end.
```
→ `compiler error: PCharToString helper not found`

So there are two faces of the same gap:
1. **Argument passing / overload match** (`MatchProcCall`): PChar is not treated
   as convertible to a string param, so the call does not match at all.
2. **Assignment**: the conversion path exists (emits a `PCharToString` helper
   call) but the helper is not always resolvable.

## Why platonic (not a lib workaround)

PXX currently compiles Synapse only because `lib/rtl/dynlibs.pas` adds an extra
**`PChar` overload** of `LoadLibrary`/`GetProcedureAddress` to dodge gap #1. That
is a workaround, not idiomatic — FPC's `dynlibs` does not need a separate PChar
overload because the language converts the argument. Once this lands, **remove
those PChar overloads** from `lib/rtl/dynlibs.pas` (string overload only) and
re-verify the synafpc probe still compiles.

## Fix sketch

- In overload/assignability checking, make `PChar` (and `PAnsiChar`) assignable
  to `string`/`AnsiString` parameters and l-values, inserting the same
  `PCharToString` conversion the assignment path already emits.
- Ensure the `PCharToString` helper is reachable from any compile that needs it
  (auto-loaded like the other System string helpers), so the assignment form
  stops failing with "helper not found" in standalone programs.
- Keep the reverse (`string` → `PChar`) behaviour unchanged.

## Done when

- `f(pc)` (PChar arg into a `const string` param) and `s := pc` both compile and
  run correctly in a standalone program (no extra `uses`).
- The PChar overloads are removed from `lib/rtl/dynlibs.pas` and Synapse's
  `synafpc` still gets past `dynlibs` ([[feature-synapse-compile-check]]).
- Regression test under `make test` covering both arg-passing and assignment.

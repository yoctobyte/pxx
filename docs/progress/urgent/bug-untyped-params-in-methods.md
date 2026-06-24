# Untyped parameters not accepted in class methods (work in standalone procs)

- **Type:** bug (parser) — language
- **Status:** urgent (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** Classes / TStream ([[feature-own-net-http-lib]]) — `TStream.Read(var
  Buffer; …)` / `Write(const Buffer; …)`.

## Symptom

An untyped `var`/`const` parameter (no type after the name) parses in a
standalone procedure but is rejected inside a **class method**:

```pascal
procedure Px(var B; n: Integer); begin end;     { OK (standalone) }

type TC = class
  function Rd(var B; n: Integer): Integer;       { ERROR }
end;
```
→ `Expected: :, but got:  (Kind: 78)` at the method's `var B` parameter.

Standalone untyped params landed earlier ([[feature-untyped-parameters]]); the
method-declaration parameter parser did not get the same path, so it demands a
`:` type after the parameter name.

## Impact

Blocks `TStream.Read(var Buffer; Count)` / `Write(const Buffer; Count)` and
`TMemoryStream` — i.e. the whole standard stream surface (synapse's heaviest
Classes need, 16 uses). Any class method with an untyped buffer parameter is
affected.

## Fix

Use the same untyped-parameter parsing in method declarations (and their
`implementation` headers) that standalone routines already accept: a `var`/
`const`/`out` parameter name with no following `:` type is an untyped param;
`@Param` yields its address.

## Done when

- The `TC.Rd(var B; n)` repro compiles and runs.
- `TStream`/`TMemoryStream` (`Read`/`Write` with untyped buffers) compile —
  together with [[bug-read-write-reserved-as-method-names]].
- Regression test under `make test`; self-host fixedpoint byte-identical.

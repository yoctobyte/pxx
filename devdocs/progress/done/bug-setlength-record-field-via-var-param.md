# SetLength on a record string/array field via a `var` parameter fails codegen

- **Type:** bug (codegen / SetLength lowering)
- **Status:** backlog (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** http keep-alive ([[feature-own-net-http-lib]]) — growing a buffer
  field of a `var conn: THttpConnection` parameter.

## Symptom

`SetLength` on a string (or dynamic-array) field reached **through a `var`
record parameter** errors at compile time:

```pascal
type TConn = record Buf: AnsiString; end;
procedure Grow(var c: TConn; n: Integer);
begin
  SetLength(c.Buf, Length(c.Buf) + n);   { error }
end;
```
→ `error: SetLength expects an array variable in IR codegen`

`SetLength` on a plain local string, and assignment to `c.Buf` (e.g.
`c.Buf := c.Buf + x`), both work — only `SetLength(c.Buf, ...)` through the
`var`-param record field is rejected.

## Workaround in use

`lib/rtl/http.pas` `HttpConnRecvMore` builds a local string and concatenates
(`SetLength(chunk, n); Move(...); conn.Buf := conn.Buf + chunk;`) instead of
`SetLength`-ing the field in place. Correct, slightly more copying.

## Fix

Make the SetLength lowering accept a field-of-var-param l-value (the same
addressable-l-value set that direct assignment already accepts), not only a
direct array/string variable.

## Done when

- The repro compiles and grows the field in place.
- Regression test under `make test`.
- Self-host fixedpoint byte-identical.

## Resolution (2026-06-25, Track A)

Fixed by generalizing the managed-string SetLength path to be **address-based**,
matching what dyn-arrays already do. Added one IR op `IR_SETLEN_STR` (target
slot-ADDRESS node + count) that calls the existing `PXXStrSetLen(addr, n)` RTL
helper. `ir.inc` now diverts SetLength on any *non-symbol* managed-string lvalue
(record/class field, var-param field, index, pointer deref) through it via
`IRLowerAddress` — no symbol reconstruction, so a field works like a plain
variable. Plain string vars (AN_IDENT) keep the existing symbol path, preserving
x86-64's amortized in-place inline resize (no O(n^2) regression).

Per-backend handler is ~5 instructions (load addr, load n, call helper) on all 6
targets. New helper `NodeIsManagedString` guards against false positives:
RecFieldType reports the *element* type for an array field, so `array of string`
fields and multidim `s[i]` sub-arrays are excluded via dyn-array depth.

Tests: `test/test_setlength_managed_field.pas` (field / var-param field / pointer-
deref field / plain var) in `make test`; verified x86-64 + i386/aarch64/arm32.
Frozen AND managed self-host both byte-identical; full `make test` + all 3 cross
gates green.

Follow-ups (not blocking): (1) Track B can drop the `lib/rtl/http.pas`
`HttpConnRecvMore` local-string-concat workaround and SetLength the field in
place. (2) Optional surface reduction: port PXXStrSetLen's geometric in-place
growth so the plain-symbol path + x86-64 inline string resize can also be
deleted.

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

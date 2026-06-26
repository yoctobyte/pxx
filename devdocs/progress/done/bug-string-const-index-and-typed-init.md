# Typed string constant with a string initializer won't parse

- **Type:** bug (parser) — typed-const string initializer
- **Status:** backlog (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-25
- **Split-from:** [[bug-set-of-char-const-corrupts-char-codegen]]

> **Update (2026-06-25, v61):** the original Symptom 1 of this ticket — untyped
> string const indexing yielding garbage (`const t = 'ABCDEF'; c := t[2]`) — is
> **FIXED** in [[bug-const-string-index-miscompiles]] (string-literal/const
> indexing now reads the right char on all targets). Only the typed-string-const
> initializer parse gap below remains.

## Symptom — typed string const with initializer → parse error

```pascal
const t: string = 'ABCDEF';
begin writeln(t); end.               { error: unexpected token () }
```

`const Name: string = '...'` (a typed string constant) is not accepted by
`ParseConstSection`; the string initializer form is unhandled for a `tyString`
typed const (only ordinal/Char/Int64/record/set typed-const initializers exist).
The untyped form (`const t = 'ABCDEF';`) works.

## Done when

- `const t: string = 'literal'` parses and the const reads back the string.
- Regression test under `make test`; self-host fixedpoint byte-identical.

## Resolution (2026-06-25, Track A)

Fixed. `ParseConstSection` had no string case in the scalar typed-const path —
it fell through to `AllocVar` + `ParseInitVal`, which has no string handler, so
the `'literal'` token was left unconsumed ("unexpected token"). Added a
`cTk in [tyString,tyAnsiString,tyFixedString,tyShortString]` branch *before*
`AllocVar` (mirroring the `tySet` guard) that registers the const in the
`StrConst` table — a read-only string-literal alias, exactly like the untyped
`const Name = 'literal'`. No storage var (a phantom would shadow + ParseInitVal
can't take a string). Covers single literal, `'a'+'b'` / `#65+'BC'` concat,
indexing, assignment, Length, and routine-local consts.

Test: `test/test_typed_string_const.pas` (in `make test`). Self-host
byte-identical; full `make test` green.

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

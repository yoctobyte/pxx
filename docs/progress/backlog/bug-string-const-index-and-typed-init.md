# Untyped string const indexing yields garbage; typed string const initializer won't parse

- **Type:** bug (codegen + parser) — two related string-constant gaps
- **Status:** backlog (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-25
- **Split-from:** [[bug-set-of-char-const-corrupts-char-codegen]] (the headline
  set-of-char/char shadowing bug is fixed in v57; these two were recorded
  alongside it and proved independent).

## Symptom 1 — untyped string const, indexed → wrong char

```pascal
const t = 'ABCDEF';
var c: char;
begin c := t[2]; writeln(c); end.    { prints garbage, not 'B' }
```

An untyped string const is expanded to a string literal over its source span
(`StrConst*` table → `AN_STR_LIT`). Indexing that with `t[2]` does not address
the literal's bytes correctly — the load picks up garbage. Worked around in
`lib/rtl/sysutils.IntToHex` by computing the hex digit arithmetically instead of
indexing a const table.

## Symptom 2 — typed string const with initializer → parse error

```pascal
const t: string = 'ABCDEF';
begin writeln(t); end.               { error: unexpected token () }
```

`const Name: string = '...'` (a typed string constant) is not accepted by
`ParseConstSection`; the string initializer form is unhandled for a `tyString`
typed const (only ordinal/Char/Int64/record/set typed-const initializers exist).

## Done when

- `t[2]` on an untyped string const yields the correct character.
- `const t: string = 'literal'` parses and the const reads back the string.
- Regression tests under `make test`; self-host fixedpoint byte-identical.

# Char-literal concatenation in a const expression fails (`const T = #65 + #66`)

- **Type:** bug (parser / const expression)
- **Status:** urgent (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-25
- **Found-by:** [[feature-synapse-compile-check]] — synacode's `ReTablebase64`
  (the Base64 reverse-lookup table) is built as `#$40 +#$40 +#$3E +…`. synacode's
  `EncodeBase64` works but **`DecodeBase64` returns garbage** (it reads that
  table), and the underlying construct is this.

## Symptom

A const whose value concatenates character literals does not parse:

```pascal
const T = #65 + #66;            { error: Expected: begin, but got: (Kind 70) }
const U = #$41 + #$42 + #$43;   { same }
```
Fails in plain mode and under `--mimic-fpc` / `{$mode delphi}`. A single char
literal const (`const C = #65;`) is fine; it is the `+` concatenation of char
literals in the constant expression that the const-expr parser rejects.

(Note: the same pattern *inside synacode* compiles — likely a different parse
context — but produces a wrong table at runtime, so DecodeBase64 yields garbage.
Either way the char-literal-concat const path is broken: it fails to parse
standalone and mis-evaluates in synacode.)

## Impact

Blocks correct `Base64`/`UU`/`XX` decoding in Synapse's `synacode` (the reverse
tables `ReTablebase64`/`ReTableUU`/… are all `#$xx + #$xx + …` consts), and any
code building a constant string from char literals — a common idiom for binary
lookup tables. (`MD5` additionally segfaults — likely a separate managed-buffer
codegen bug on its `Move` path; track separately if it is not this.)

## Fix

The constant-expression evaluator/parser should accept `+` between character
literals (and between char literals and string literals) as string
concatenation, producing the concatenated constant string — in every mode.

## Done when

- `const T = #65 + #66;` parses and `T = 'AB'` (Length 2, Ord 65/66); the
  `#$xx + #$xx` form likewise.
- `synacode.DecodeBase64(EncodeBase64(s)) = s` round-trips.
- Regression test under `make test`; self-host fixedpoint byte-identical.

## Resolution (2026-06-25, v60)

Fixed the untyped-const parse path. `#65` and `'A'` both lex as `tkString`
tokens carrying the decoded value in `SVal`; the untyped string-const branch in
`ParseConstSection` only handled a SINGLE literal (it captured one token's source
span) and fell over on the trailing `+`.

Fix (`parser.inc`): when a `+` follows the string literal, concatenate the
decoded values of the `+`-separated string/char literals into a fresh `TokChars`
span and point the string const at it — a use expands to an `AN_STR_LIT` over
that span, exactly like a single literal. Works for `#65 + #66`, `#$41 + #$42`,
`'foo' + 'bar'`, and mixed `'x' + #45 + 'y'`, in every mode.

Verified: `const T = #65 + #66` → `T = 'AB'` (Length 2; assigning to a string var
and indexing gives Ord 65/66). Regression `test/test_const_string_concat.pas`
under `make test`. Self-host byte-identical; pinned v60.

Note: the synacode `DecodeBase64` round-trip (and the "compiles-but-wrong-table
inside synacode" observation) can't be verified yet — synacode/synapse still stop
on unrelated gaps (e.g. "untyped parameter requires var, const, or out"). The
headline const-concat parse + value is fixed; re-probe synacode once those land.

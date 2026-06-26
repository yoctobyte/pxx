# Capitalized keywords not recognized (case-sensitive keyword table)

- **Type:** bug (Track A — lexer)
- **Status:** DONE — 2026-06-23 (7d5b18d).
- **Owner:** — (Track A)
- **Opened:** 2026-06-23
- **Closed:** 2026-06-23
- **Found by:** Track A, following the capital-`array` keyword fix
  ([[project_synapse_recon_array_keyword]]) — the table was inconsistent.

## Problem

Pascal keywords are case-insensitive in user code, but the lexer's `Keyword()`
table matched most keywords by hard-coded lowercase characters (with ad-hoc
`Capital`-first variants for only some). So capitalized / mixed-case reserved
words fell through to identifiers and broke common mixed-case FPC/Delphi source:

```
Then Else Type Mod Case  ->  "Expected then/begin/), but got Then/Type/Mod/Case"
BEGIN END For To Do ...   ->  same class
```

Only `array` had been fixed individually before this.

## Fix

`Keyword()` (lexer.inc) now lowercases the token once up front when
`not CaseSensitiveMode` (user code), so every existing table entry matches any
case. The compiler's own source is `{$CASESENSITIVE ON}`, so it keeps exact
matching and self-host stays byte-identical.

One exception: `forward` is a DIRECTIVE, not a reserved word — FPC allows it as an
ordinary identifier (`procedure Forward(...)`, used in
`test/test_managed_var_param.pas`). A non-exact-case match of `forward` reverts to
an identifier, so `forward` (lowercase) is the directive while `Forward`/`FORWARD`
stay identifiers.

## Verification

`test/test_keyword_case.pas` (Type/For/To/Do/If/Then/Else/Mod/Case mixed-case),
FPC objfpc oracle-matched (9 / 22). `test/test_keyword_array_case.pas` still
green. make test + cross-bootstrap byte-identical; the `Forward`-as-identifier
test (test_managed_var_param) passes.

# feature: binary integer literals (`%1010`)

- **Type:** feature (Track A — lexer)
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** low (cosmetic; hex `$..` works, decimal works)

## Gap

FPC accepts `%`-prefixed binary integer literals; pxx does not:

```pascal
begin writeln(%1010); end.   { fpc: 10    pxx: error: unexpected character }
```

## Expected

Lex `%` followed by `0`/`1` digits as a binary integer literal (FPC syntax).
Handy for bit masks / register fields (ESP work). Hex (`$FF`) already lexes.

## Repro

`tools/fpc_diff_probe.sh` (`binary-literal`).

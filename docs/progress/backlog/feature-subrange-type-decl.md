# feature: named subrange type declaration (`type T = lo..hi`)

- **Type:** feature (Track A — parser)
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** low-medium (inline subrange works; only the named form is missing)

## Gap

A subrange used inline in a var declaration works, but naming it as a type fails:

```pascal
var x: 1..10; begin x := 5; writeln(x); end.        { pxx: 5  (ok) }

type tr = 1..10; var x: tr; begin x := 5; writeln(x); end.
{ fpc: 5    pxx: error: unexpected token  (at the subrange in a type decl) }
```

## Expected

Accept `type Name = lo..hi;` (ordinal subrange type), usable like the inline
form — and as an array index type, set base, case selector, etc.

## Repro

`tools/fpc_diff_probe.sh` (`subrange-type`).

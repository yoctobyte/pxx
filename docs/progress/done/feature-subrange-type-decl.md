# feature: named subrange type declaration (`type T = lo..hi`)

- **Type:** feature (Track A — parser)
- **Status:** done
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

## Resolution (2026-06-23)

Parser (ParseTypeSection type-def dispatch): a `type T = lo..hi` whose def starts
with a constant (tkInteger/tkMinus/char-literal) is parsed as an ordinal subrange
and registered as an alias to the base ordinal (tyChar for a char-literal bound,
else tyInteger) — same treatment as an inline `var x: lo..hi` (bounds not
retained). `type tr = 1..10` / `type tc = 'a'..'z'` usable as var types,
byte-identical to FPC. Front-end only. Closes feature-subrange-type-decl.

# feature: enumerated type with explicit ordinal values

- **Type:** feature (Track A — parser)
- **Status:** done
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** low-medium (common for C-interop / protocol constants)

## Gap

Assigning explicit ordinal values to enum members is rejected:

```pascal
type te = (a = 1, b = 5, c = 10);
begin writeln(ord(a), '|', ord(b), '|', ord(c)); end.
{ fpc: 1|5|10    pxx: error: unexpected token  (at '=') }
```

Plain enums (`(a, b, c)` → 0,1,2) and `Ord` on them already work.

## Expected

Accept `(name = constexpr, ...)`; members without a value continue from the
previous (FPC semantics). Useful for mapping enums onto C/protocol numeric
constants (ESP/IDF, wire formats).

## Repro

`tools/fpc_diff_probe.sh` (`enum-explicit`).

## Resolution (2026-06-23)

Parser (enum decl in ParseTypeSection): each member now accepts an optional
`= constexpr` ordinal; a valueless member continues from the previous value + 1
(FPC semantics). `(a=1, b=5, c, d=10)` -> 1,5,6,10, byte-identical to FPC.
Front-end only. Closes feature-enum-explicit-values.

# feature: enumerated type with explicit ordinal values

- **Type:** feature (Track A — parser)
- **Status:** backlog
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

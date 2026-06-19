# `uses sysutils` is hard-skipped — a real lib/rtl/sysutils can't load

- **Type:** bug (compiler)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (discovered by Claude B providing RTL conversions)

## Symptom

`compiler/parser.inc:8920`:

```pascal
if (lo = 'sysutils') or (lo = 'baseunix') or (lo = 'unix') then Exit;
```

`uses sysutils` is treated as a no-op and never loads a unit source. So a real
`lib/rtl/sysutils.pas` providing `IntToStr` / `Copy` / `Trim` / `StrToInt` /
`Val` etc. cannot be picked up — the unit resolves to nothing and the symbols
stay undefined. (A unit under any other name, e.g. `strutils`, loads from
`lib/rtl` normally.)

## Impact

Track B has to house SysUtils-family helpers in `lib/rtl/strutils.pas` as an
interim home (see commit `lib(strutils): IntToStr`). FPC code idiomatically does
`uses sysutils`, so the canonical home should work. This is the natural landing
spot for the feature-rtl-conversion-and-bitset-library surface.

## Direction

Make the skip conditional: if a `sysutils` (`/baseunix`/`unix`) unit source
exists on the search path, load it normally; only short-circuit when it is
absent (preserving today's behavior of letting FPC `uses sysutils` pass on a
codebase that relies purely on builtins). Then track B migrates the conversion
helpers from `strutils` into `lib/rtl/sysutils.pas`.

## Log
- 2026-06-19 — opened by track B. Confirmed `strutils` (non-skipped name) loads
  fine; only the three skip-listed names are blocked.

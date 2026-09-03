---
type: bug
track: A
prio: 90
status: open
summary: Under -dPXX_SHORTSTRING, passing a frozen record FIELD to an AnsiString
  parameter is refused by overload resolution on ALL SEVEN targets; a plain
  variable of the same type is accepted, and both compile in the default mode.
---

# A frozen record field is refused by overload resolution against an AnsiString parameter

**Phase-4 blocker on every target — the first one that is not target-specific,
and the first that touches wasm32 and xtensa at all.**

```pascal
program ov;
type R = record f: string[10]; end;
procedure Show(const a: AnsiString); begin WriteLn('[', a, ']'); end;
var r: R; s: string[10];
begin r.f := 'field'; s := 'plain'; Show(s); Show(r.f); end.
```

```
error: no overload of Show matches these arguments
  argument types: (ShortString)
    Show(AnsiString)
  near: Show ( r . f ) >>> ; end .
```

Measured at `4a84ba4b5`, compiler sha `e102360f2c11`:

| target | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| x86-64, i386, arm32, aarch64, riscv32, wasm32, xtensa | compiles, `[plain]` `[field]` | **refused, all seven** |

**`Show(s)` on a plain variable is ACCEPTED in the same program; only the FIELD
is refused.** A bare variable normalises to `tyString` via `StrValTk` while a
field load keeps `tyShortString`, so the field is the operand that reaches
overload resolution with the narrow kind.

`TypesCompatible` in `symtab.inc` carries the frozen-param ← managed-arg rule
and not the reverse.

## Why this one is different from the rest of the family

Every other byte-prefix defect found so far is a wrong VALUE or a crash on one
or two targets. **This is a compile-time refusal on all seven**, so it cannot be
missed at runtime and cannot be hidden by a guard — but it also means the flip
cannot land anywhere until it is fixed. Ranked above the concat and `Copy`/`Pos`
crashes for that reason.

**It is an honest refusal, not a miscompile** — the compiler declines rather
than emitting something wrong, which is the right failure.

## Provenance

Found by franka-29 while building the regression battery for the i386 fixes
(`21544412b`), reported to the coordinator rather than taken silently.
Independently reproduced and extended from five targets to all seven here,
including wasm32 and xtensa (xtensa needs `--platform=posix
--xtensa-soft-mulhigh`; bare `--target=xtensa` is the ESP profile and refuses
for unrelated reasons).

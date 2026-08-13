---
track: A
prio: 40
type: bug
blocked-by: []
summary: "`f(fmt, ['a'])` stops compiling when the routine is in a CROSS-UNIT overload set and its unit is used LAST: the literal is typed (ShortString, set) against an `array of const` parameter reported as `record`. Same-unit overload sets are fine, single cross-unit routines are fine, and reversing the uses order fixes it — so the array-of-const conversion is lost on one path through the cross-unit merge."
---

# An `array of const` literal does not match once the name is a cross-unit overload set

Found 2026-08-13 while examining whether NilPy's `format(v, spec)` builtin could
be declared in pylib alongside sysutils' `Format(fmt, [args])` instead of being
intercepted in the parser. It cannot — because of this.

## Measured, four rows that isolate it

Two units, each declaring `g` with `overload`; `uc` takes
`(const fmt: AnsiString; const args: array of const)`, `ud` takes
`(const v: Variant; const spec: AnsiString)`.

| shape | result |
| --- | --- |
| `uses uc;` alone — `g('%s', ['a'])` | **compiles**, prints `fmt:%s` |
| both overloads in ONE unit (or the program) | **compiles**, both calls resolve |
| `uses uc, ud;` — array-of-const unit FIRST | **compiles**, both calls resolve |
| `uses ud, uc;` — array-of-const unit LAST | **FAILS** |

The failing diagnostic:

```
error: no overload of g matches these arguments
  argument types: (ShortString, set)
  candidates:
    g(Variant, AnsiString)
    g(AnsiString, record)
```

So the merge itself works — both candidates are listed — but the caller-side
`['a']` was never turned into an array-of-const constructor: it is still a `set`
literal, and the parameter is reported as `record`. Something on that path
builds the candidate list without telling the argument side that an
`array of const` conversion is available.

**Order-dependent, and in the direction that bites us:** the failure needs the
array-of-const routine's unit to come LAST, which is exactly sysutils' position
in a NilPy program (pylib is pulled first, imports after).

## Why it matters beyond the one call

It is the reason `format` had to become a frontend intercept rather than a pylib
declaration — see [[decide-nilpy-builtin-vs-pascal-unit-name-resolution]]. Fixing
this unblocks the clean route: `overload` on both declarations makes pxx merge
cross-unit sets correctly (proved by row 3), which is the FPC-faithful mechanism
for exactly this situation and would generalise to every future collision
instead of costing a parser arm per name.

It is also a defect in its own right: any two units that both export a name,
one of them with an `array of const` parameter, hit it — and the failure looks
like the CALL is wrong when nothing is wrong with it.

## Where to look

`MatchCallDelphiProcAddr` is the one entry into `MatchProcCall*`
(project_overload_resolution_single_side_channel_entry), and the same-unit path
already gets this right, so the question is what the cross-unit candidate walk
does differently — the argument is reported as `set`, which is the type the
literal has BEFORE the open-array conversion, so the conversion decision is
being made too late or on the wrong list.

## Gate

The four rows above as a `.pas` test (three compile-and-run, one currently
failing), `Format(fmt, [args])` from sysutils still resolving with and without
`overload` on it, plus self-host byte-identical.

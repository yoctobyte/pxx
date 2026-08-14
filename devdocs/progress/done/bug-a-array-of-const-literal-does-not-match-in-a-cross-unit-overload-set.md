---
track: A
prio: 40
type: bug
blocked-by: []
summary: "`f(fmt, ['a'])` stops compiling when the routine is in a CROSS-UNIT overload set and its unit is used LAST: the literal is typed (ShortString, set) against an `array of const` parameter reported as `record`. Same-unit overload sets are fine, single cross-unit routines are fine, and reversing the uses order fixes it — so the array-of-const conversion is lost on one path through the cross-unit merge."
status: done
owner: agent-AN
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

## Resolution

The ticket's "where to look" was right: the conversion decision *was* being made
on the wrong list. It was not made too late — it was made too NARROWLY.

`ParamIsVarRecArray(procIdx, argNo)` asked exactly one candidate: whichever the
name resolved to first. The parser has to answer "is this `[...]` a TVarRec
vector or a set literal?" **before** overload resolution, because the answer
determines how the brackets are parsed at all — so with the array-of-const
routine in the unit listed last, the question was put to the OTHER overload,
answered "no", and the literal was parsed as a set. Overload matching then saw
`(ShortString, set)` and could not match a candidate it had correctly found.
That is why the diagnostic listed both candidates: the cross-unit merge was
never the problem.

### Fix

`ParamIsVarRecArray` now asks the whole visible overload set, via the same
`ProcChainHead` / `ProcHashNext` walk the diagnostic's own candidate list uses.
The strict single-proc test is preserved as `ParamIsVarRecArrayAt`, and the walk
only runs when the first answer is no and the routine carries `overload` — so
nothing that worked before takes a different path.

Because the six call sites (plain call, method-through-chain, statement
position, NilPy argument binding, …) all go through this one function, fixing it
fixed all of them at once, rather than adding a seventh place that has to know.

### Measured

| shape | before | after |
| --- | --- | --- |
| `uses uc;` alone | compiles | compiles |
| both overloads in ONE unit | compiles | compiles |
| `uses uc, ud;` (array-of-const FIRST) | compiles | compiles |
| **`uses ud, uc;` (array-of-const LAST)** | **fails** | **compiles, both calls resolve** |

**FPC 3.2.2 accepts the failing program**, confirmed by building the same two
units and program with `{$mode objfpc}`: it prints `fmt:%s`, as pxx now does.

`Format(fmt, [args])` from sysutils still resolves in every shape tried —
multi-argument, single-argument, empty `[]`, and a `Single` argument.

### The residual corner, escalated not guessed

A SET parameter at the same slot vetoes the reinterpretation, so a genuine set
literal is not stolen. But a BRACKET LITERAL where one overload takes
`set of T` and another takes `array of const` at the same slot has no reference
answer to copy: **FPC 3.2.2 is itself uses-order dependent there and flips**
(`k-aoc` one way, `k-set` the other), while pxx is order-independent and always
reads `array of const`. Measured both directions in both implementations and
filed as [[decide-set-vs-array-of-const-at-the-same-overload-slot]]; the
regression test deliberately asserts only the unambiguous form, because pinning
the other would cement an accident.

### Test

`test/test_array_of_const_cross_unit_overload.pas` plus two helper units, in the
failing uses order, covering one-, two- and zero-element literals, the sibling
overload, and the set-parameter case. Wired into the Makefile.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary). Parser only, no frozen builtin, so no re-pin.

### What this unblocks

The ticket noted this was why NilPy's `format` had to be a frontend intercept
rather than a pylib declaration alongside sysutils' `Format`
([[decide-nilpy-builtin-vs-pascal-unit-name-resolution]]). That route is now
open — not taken here, since it is a separate change with its own gate.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.

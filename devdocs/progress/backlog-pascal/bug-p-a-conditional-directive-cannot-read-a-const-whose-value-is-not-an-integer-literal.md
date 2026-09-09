---
slug: bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal
title: "`{$if}` cannot read a `const` whose value is a set or a folded call"
track: P
prio: 35
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-09
tags: [conditional-directives, lexer, fpc-corpus]
blocked-by: []
summary: "`{$if}` reads a source `const` now (abc681636) -- but only one whose value is an INTEGER LITERAL. Two shapes in FPC's compiler are not: `{$if (cs_opt_use_load_modify_store in supported_optimizerswitches)}` (nld.pas:700) needs the `in` operator over a SET constant that is itself built by adding three other set constants (x86_64/cpuinfo.pas:205), and `{$if declared(RS_STACK_POINTER_REG) and (RS_STACK_POINTER_REG<>RS_INVALID)}` (rgobj.pas:1728) needs `RS_INVALID = high(tsuperregister)` (cgbase.pas:400), a const whose value is a FOLDED CALL. Three of FPC's 207 compiler units stop on these two -- nld and ncnv on the first (one directive, reached twice: ncnv uses nld), rgobj on the second. Measured at fcbe280b7; they are the WHOLE remaining conditional-directive family, down from 26 units."
---

# `{$if}` over a const that is not an integer literal

The const door added by
[[bug-p-a-conditional-directive-cannot-read-a-constant-or-a-type-the-source-declares]]
matches `NAME = <integer literal> ;` and deliberately nothing else — that
ticket's own "what must NOT be widened" section says a name whose value is an
EXPRESSION should keep the current error rather than be guessed at. These are
the two expression shapes the corpus actually asks for, so they are the
evidence that would widen it.

- **Umbrella:** `umbrella-pxx-compiles-fpc-itself`

## The two shapes, with the FPC unit and line that produced each

**1. Set membership, 2 units (nld, ncnv).** `nld.pas:700`:

```pascal
{$if (cs_opt_use_load_modify_store in supported_optimizerswitches)}
```

`supported_optimizerswitches = genericlevel1optimizerswitches + ...`
(`x86_64/cpuinfo.pas:205`) — so answering it needs a set-valued constant
folded from three other set-valued constants, and then an `in`. pxx answers
`conditional directive: expected operator` at the `in`. **ncnv is the same
directive, not a second one**: ncnv's interface `uses nld`.

**2. A const whose value is a folded call, 1 unit (rgobj).** `rgobj.pas:1728`:

```pascal
{$if declared(RS_STACK_POINTER_REG) and (RS_STACK_POINTER_REG<>RS_INVALID)}
```

with `RS_INVALID = high(tsuperregister)` at `cgbase.pas:400`. pxx answers
``conditional directive: `RS_INVALID` has no integer value here``. This half is
the smaller of the two and shares its machinery with `ConstEvalOrdBound`, which
already folds `low`/`high`/`pred`/`succ` — the const walk is at TOKEN level and
has no type, which is the actual gap.

## What works already, so the boundary is exact

Measured at `fcbe280b7`, all byte-identical to fpc 3.2.2: an integer const in
this file or a used unit, a hex const, a negative const compared with `<`,
two source consts compared with each other, `sizeof` through a one- or two-hop
type alias in either file, `sizeof(pointer) > sizeof(TAlias)` and
`declared(X) and (X <> Y)` over integer consts. (`defined(X)` also answers, and
was checked against pxx only -- it is not one of the fpc-verified rows.) The fixture is
`test/test_p_a_conditional_directive_can_read_a_source_const.pas`.

## Why prio 35

Three units of 207, and both shapes are behind
[[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]]
anyway — no unit here compiles when this is fixed. It is filed so the corpus
row has an owner, not because it is next.

---
track: P
prio: 60
type: bug
blocked-by: []
summary: "A set literal's elements are never checked against the set's element type. `TakesSet(['a', 1])` on a `set of TDay` parameter compiles and answers dTue; `[cGreen]` (a DIFFERENT enum) silently becomes dTue; `[True]` works; `[99]` silently produces the empty set with no diagnostic. FPC rejects every one of them. No overloading needed — one procedure, one set parameter."
status: done
owner: plexus-APN
---

# Set literal elements are not type-checked against the element type

Found while investigating
[[decide-set-vs-array-of-const-at-the-same-overload-slot]] — that ticket's
`['a', 1]` row turned out not to be about overloading at all. Measured against
`stable_linux_amd64/default/pinned` v339 /
f11e0ed9816edc1d57ef8ee6e6ab0e5b9885db6c, with FPC 3.2.2 as the oracle.

## Repro — no overloading anywhere

```pascal
{$mode objfpc}
program iso;
type
  TDay   = (dMon, dTue, dWed);      { ord 0..2 }
  TDays  = set of TDay;
  TColor = (cRed, cGreen, cBlue);   { a DIFFERENT enum, same ordinal range }

procedure TakesSet(d: TDays);
begin
  if dTue in d then WriteLn('dTue is in the set') else WriteLn('it is not');
end;

begin
  TakesSet(['a', 1]);
end.
```

pxx prints **`dTue is in the set`**. FPC: `Incompatible types: got "ShortInt"
expected "Char"`.

## The whole surface, one row per shape

| literal into `set of TDay` | pxx | FPC 3.2.2 |
| --- | --- | --- |
| `[dTue]` | `{1}` — correct | accepted |
| `[1]` | `{1}` — a bare integer | `Incompatible type ... Array of ShortInt, expected TDays` |
| `['a', 1]` | `{1}` — a Char and an Integer | `Incompatible types: got ShortInt expected Char` |
| `[cGreen]` | `{1}` — **a different enum type** | `... Array of TColor, expected TDays` |
| `[99]` | `{}` — out of range, **silently dropped** | `... Array of ShortInt, expected TDays` |
| `[True]` | `{1}` — a Boolean | `... Array of Boolean, expected TDays` |

## Two defects, and both are silent

1. **No element type check.** Anything ordinal goes in. `[cGreen]` answering
   `dTue` is the sharpest: two unrelated enums are freely interchangeable inside
   a set literal, so a refactor that swaps one enum for another cannot be caught
   by the compiler anywhere a set literal is involved.
2. **Out-of-range members vanish.** `[99]` on a 3-element enum yields the empty
   set: no compile error and no run-time complaint — the value simply never
   lands in the mask. There is no diagnostic at any level, and pxx has no
   range-check switch to raise one (`-Cr` is FPC's; pxx rejects it as an unknown
   option).

Both are the class this repo calls the expensive one: no crash, a plausible
wrong value, far from the cause. `dTue in d` answering True for a set built from
`['a', 1]` is a conditional silently taking the wrong branch.

## Why it matters beyond correctness: it is blocking a design decision

[[decide-set-vs-array-of-const-at-the-same-overload-slot]] asks what `f([x])`
should mean when one overload takes a `set of T` and another an
`array of const`. **pxx cannot use the bracket contents to disambiguate while
this bug exists**, because *every* bracket list is a valid set literal. Fix
this and the ambiguity shrinks to the genuine ties — `[dTue]`, `[dMon, dWed]`,
`[]`, where the elements really are members of the set type — which is a far
smaller thing to legislate. That decide ticket is now scoped to the residual.

## How FPC does it, which is the fix shape

FPC does **not** commit at parse time. `[...]` always becomes a neutral
`tarrayconstructornode` (`pexpr.pas:3375-3400`, with `carrayconstructorrangenode`
for `a..b`), and the conversion to a set happens later, driven by the TARGET
type — `arrayconstructor_to_set` in `htypechk.pas:3000`, guarded by
`(def_to.typ=setdef) and is_array_constructor(...)`. The element check falls out
of that conversion: it knows the destination set's element type because it is
converting *to* it.

pxx commits at parse time instead, from the candidate's parameter shape, and
never looks inside the brackets. That single representational difference
explains this bug *and* every row of the order-dependence table in the decide
ticket. Per `root-cause-over-microfix.md`, deferring the decision the way FPC
does is the overhaul that deletes cases rather than adding them — it would close
this ticket and most of that one together. Bolting an element-type check onto
the existing parse-time path is the microfix; it fixes the silent wrong value
(which is the urgent half) but leaves the representation that produced it.

Decide which deliberately and say so in the fix.

## Gate

`make compiler/pascal26` + the six-row repro above, then `tools/gate.sh quick`.
Resolution touches the shared `parser.inc` type paths, so **`--tier limited` at
minimum** per `devdocs/dev/name-resolution.md` §3.

Expect the SELF-HOST to be the loudest test, not the suite: `compiler/**` is
written in this dialect and uses set literals throughout (token sets, type-kind
sets), so a stricter element check runs against tens of thousands of bracket
expressions the moment the compiler recompiles itself. Budget for that finding
real code rather than assuming the tree is clean — and note the tree compiling
today proves nothing, since today there is no check to fail.


## Resolution — 2026-08-16, deliberately the MICROFIX, and here is why

The ticket asked for the choice to be stated. **Microfix: an element check on
the existing parse-time path.** FPC's deferral (a neutral array-constructor node
converted by the target type) is still the right end state and is NOT done here.

What changed the calculus: the parser already consults the target parameter
before parsing `[...]` at all — `ParamIsVarRecArray` / `ParamIsOpenArrayScalar`
decide whether the brackets are a TVarRec vector, an array constructor or a set.
So the target type was never actually missing at parse time. It was consulted
for the literal's SHAPE and then not for its CONTENTS. Adding the second use of
an existing lookup is a much smaller thing than the representational change, and
it removes the silent wrong value today.

### The rule — one, not six

> In a literal bound to a `set of TEnum`, every constant element must be a
> member of THAT enum.

That single rule subsumes the entire reported table. A plain integer, a char,
`True` and an out-of-range ordinal are all "not a member of TEnum"; so is a
member of a DIFFERENT enum with the same ordinal, which was the sharpest case.
Sets whose element type is not an enum (`set of Char`, `set of Byte`,
`set of 0..7`) are left completely alone, and `[]` is always legal.

A second rule needs no target at all and so fires everywhere, including at an
assignment: **a literal may not mix members of two different enums.**

### Where it is enforced

| context | before | now |
| --- | --- | --- |
| `f([...])`, plain call | silent | checked |
| `f([...])`, method / `obj.m([...])` | silent | checked |
| `x in [...]` (both the constant fast path and the runtime path) | silent | checked, target = the LEFT operand's enum |
| `[...]` mixing two enums, anywhere | silent | rejected |
| **`setvar := [...]`** | silent | **still silent — see residual** |

The `in` arm needed no plumbing (the left operand is right there). The call arm
did: a param symbol does not outlive the callee's scope and `Params[].SymIdx` is
-1, so the element enum is now persisted in **`ProcParamSetEnumId`**, a parallel
array exactly like `ProcParamRecId` and durable for the same reason.

### Measured

Both forms, all six reported rows, now agree with FPC on accept/reject:

```
                 call arg          x in [...]
[dTue]           ok                ok
[1]              REJECTED          REJECTED
['a', 1]         REJECTED          REJECTED
[cGreen]         REJECTED          REJECTED     "set of TColor element in a set of TDay"
[99]             REJECTED          REJECTED
[True]           REJECTED          REJECTED
[]               ok                ok
[dMon..dWed]     ok                ok
[cRed, dTue]     REJECTED          REJECTED     (target-free rule)
```

`test/test_set_literal_element_types.pas` is the positive half — 15 legal
shapes (`set of Char`, `set of Byte`, ranges, a runtime element, `+`/`-`, a
typed const, `Include`/`Exclude`), and its `.expected` is **FPC's own output**,
so it pins that the tightening cost no legal literal. Two `%FAIL` negatives
pin the diagnostics. All three wired into `test-core`.

**The self-host was the loudest test, as predicted — and it was silent.** The
compiler is written in this dialect and uses enum set literals throughout
(token sets, type-kind sets); it recompiles itself byte-identically with the
check on, first try and every time since. So the tree really was clean.

### Residual, filed rather than hidden

1. **`setvar := [...]` is still unchecked** (the mixed-enum rule reaches it, the
   target rule does not). Assignment RHS parsing is spread over many sites and
   none of them was the one choke point; chasing them one at a time is exactly
   the microfix-on-a-microfix this repo warns about. This is the strongest
   remaining argument for the FPC-style deferral, because a target-driven
   conversion has ONE site by construction.
2. **Overloaded routines skip the target rule** — at parse time `procIdx` is the
   candidate the name resolved to first, not necessarily the one the call binds.
   The target-free mixed rule still applies. Deliberately conservative: a wrong
   diagnostic is worse than a missing one.
3. **Non-enum sets get no range check** — `[99]` into a `set of 0..7` still
   drops silently. Untouched here on purpose; it is a different mechanism
   (the mask width), not the element-type check.
4. The representational overhaul remains the right end state and remains open.

`decide-set-vs-array-of-const-at-the-same-overload-slot` is now better placed:
a bracket list is no longer trivially a valid set literal for every element
type, so the genuine ties are what is left to legislate.

### Gate

`make compiler/pascal26` (self-host fixedpoint, converged round 1), the six-row
repro in both forms, the FPC differential on the positive test, and
`tools/gate.sh quick` — GREEN.

## Log
- 2026-08-16 — resolved, commit af588ad66.

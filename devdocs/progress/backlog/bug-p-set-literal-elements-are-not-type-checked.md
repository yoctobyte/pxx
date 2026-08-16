---
track: P
prio: 60
type: bug
blocked-by: []
summary: "A set literal's elements are never checked against the set's element type. `TakesSet(['a', 1])` on a `set of TDay` parameter compiles and answers dTue; `[cGreen]` (a DIFFERENT enum) silently becomes dTue; `[True]` works; `[99]` silently produces the empty set with no diagnostic. FPC rejects every one of them. No overloading needed — one procedure, one set parameter."
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

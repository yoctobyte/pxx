---
track: P
prio: 45
type: compat
blocked-by: []
summary: "The variadic `Concat` intrinsic is shadowed by `sysutils`'s two-argument `Concat`, so `uses sysutils` breaks `Concat('a','b','c')` — which compiles fine without it. The shadow rule is `procIdx < 0`, i.e. ANY user Concat disables the intrinsic outright. Loud, not silent."
status: done
owner: opus5-frank1
---

# `uses sysutils` breaks three-argument `Concat`

- **Track P** (Pascal frontend: the `Concat` intrinsic's shadow rule), tag
  **compat-pascal**.
- Found 2026-08-20 by an FPC differential probe over the string RTL. The first
  reading of the finding — "pxx's Concat only takes two arguments" — was wrong,
  and the correction is the whole ticket.

## Repro

```pascal
program cc;
begin
  Writeln(Concat('a', 'b', 'c'));    { prints abc }
end.
```

```pascal
program cc2;
uses sysutils;
begin
  Writeln(Concat('a', 'b', 'c'));    { error: no matching overload }
end.                                 {   candidates: Concat(AnsiString, AnsiString) }
```

pxx **does** have the variadic intrinsic — `ParseFactorCore` folds
`Concat(s1, ..., sn)` into a chain of `+`. It is guarded by `procIdx < 0`
("a user `Concat` shadows it"), and `sysutils` declares a two-argument `Concat`,
so importing sysutils silently withdraws the intrinsic and leaves the pair.

## Why the shadow rule is too coarse

Shadowing a builtin with a user routine of the same name is right; withdrawing
it for argument counts the user routine cannot accept is not. FPC keeps the
intrinsic and `uses sysutils` changes nothing there.

## Sketch

Two ways, both small:

- **Frontend:** relax the guard from "no user Concat exists" to "no user Concat
  overload accepts this argument count" — the call's comma count is available
  from the token stream before the arguments are parsed, which is how the
  existing lookahead in this arm already works.
- **Library:** drop `Concat` from `lib/rtl/sysutils` entirely, since the
  intrinsic covers the two-argument case as well. That is a Track B edit and
  fixes the symptom without fixing the rule.

The frontend one is the honest fix: any other unit declaring a `Concat` hits the
same wall.

## Outcome — 2026-08-27

The frontend fix, as the ticket asked. But **not** the frontend fix the ticket
sketched — measurement moved it one step further, and the step matters.

### The sketched rule would not have been enough

The sketch was *"relax the guard from 'no user Concat exists' to 'no user Concat
overload accepts this argument COUNT'"*. Written, built, and then measured
against the dynamic-array form:

```pascal
c := Concat(a, b);       { two dynamic arrays }
```

`sysutils.Concat` has exactly the right ARITY for that call and entirely the
wrong types, so an arity rule leaves it broken — and the ticket's own repro
section never covered it because the reported symptom was the three-string case.

### Where the rule went instead

`Copy` already had this exact problem and already had the answer: **two arms,
one for "no such routine is in scope at all" and one at the point where overload
matching has FAILED**. Its comment says so, and says the two must stay in step:

> which path a program takes depends on whether a `Copy` function is in scope at
> all, so fixing only one made `Copy(a)` compile without `uses sysutils` and fail
> with "no overload of Copy matches" with it.

So `Concat` gets the same pair. The bare-intrinsic arm in `ParseFactor` keeps
`procIdx < 0` — it is for a program with no `Concat` anywhere. When one IS in
scope the call goes down the ordinary overload path, and the intrinsic is picked
up again beside the `Copy` fallback, where whether the user's `Concat` accepts
these arguments has been *decided* rather than guessed. Nothing is withdrawn on
a guess, and a real `sysutils.Concat(s1, s2)` is never shadowed.

Guarded on the first argument being a dynamic array or a string/char, exactly as
the `Copy` arm is guarded on a dynamic array. Without that guard a plainly wrong
`Concat(rec1, rec2, rec3)` folds into `rec1 + rec2 + rec3` and is reported as a
missing `+` overload instead of as the wrong call it is — verified: it still says
`no overload of Concat matches these arguments  argument types: (record, record,
record)`.

### The library option was not taken, and is now unnecessary

The ticket's alternative was to drop `Concat` from `lib/rtl/sysutils`. Worth
recording why FPC never hits this at all: **FPC's own sysutils does not declare
`Concat`** — it is a System-unit intrinsic there, so there is nothing to shadow.
That makes the library edit look attractive, and it is still the reason nobody
noticed for so long. It was not taken because it fixes one unit and not the
rule; any other unit declaring a `Concat` walks into the same wall.

One place where pxx now accepts what FPC rejects, deliberately: with a
USER-declared `function Concat(const a, b: string): string` in the program,
`Concat('a','b','c')` folds to the intrinsic here and is
`Wrong number of parameters specified for call to "Concat"` under FPC. Accepting
a form FPC rejects is not a defect (CLAUDE.md), and the alternative — a rule that
distinguishes "declared in a unit" from "declared in the program" — would be a
worse rule than the one being replaced.

### Measured

`test/test_concat_survives_uses_sysutils.pas` (+ `.expected`, wired into
`test-core`), under `uses sysutils`, byte-identical to `fpc -O1 -Mobjfpc` 3.2.2:

| call | before | after / FPC |
| --- | --- | --- |
| `Concat('a','b','c')` | **no overload matches** | `abc` |
| `Concat('a','b')` | `ab` (sysutils', unshadowed) | `ab` |
| `Concat('solo')` | **no overload matches** | `solo` |
| `Concat(s,'y','z')` | **no overload matches** | `xyz` |
| `Concat('n=', IntToStr(42))` | `n=42` | `n=42` |
| `Concat(a, b)` — arrays | **no overload matches** | `1 2 3 4` |
| `Concat(a, b, a)` — arrays | **no overload matches** | `1 2 3 4 1 2` |

### Gate

`make compiler/pascal26` byte-identical (0ab02bb00edb) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0 · fgl 7/7.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.

---
track: P
prio: 25
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-06
resolved-by: frankS
summary: "FIXED AT BOTH ADDRESSES, and the reason it was released as unfixable was a half-truth. Two ARRAY parameters at the slot a `[...]` lands on could not be separated and fell through to first-declared: `P2(N: Integer; A: array of Integer)` / `P2(N: Integer; A: array of const)` with `c.P2(2, [7, 8])` ran the Integer body where fpc 3.2.2 runs the array-of-const one, and the constructor door (ClassCtorArraySigAt) had the same property one level worse -- it decides how the bracket is PARSED, so an `array of const` ctor declared second received an Integer vector. The ticket argued no ranking was possible because the speculative probe cannot parse a bracket argument. True of ranking by the ARGUMENT; fpc's actual rule uses no argument at all -- `array of const` takes a bracket slot UNCONDITIONALLY, measured in both declaration orders against array of Integer/string/Double/Byte with integer, string, float and empty `[]` element lists, winning even where the elements could not convert to the other candidate. That is a property of the PARAMETERS and it was available all along. Fixed in FindUMethOverloadAhead (nVR/vrOnly, behind the existing tySet veto, which is untouched) and in ClassCtorArraySigAt (two passes). Fixture test_p_an_array_of_const_wins_a_bracket_argument, 12 rows, every family in BOTH orders; 5 move against the pinned pre-fix compiler and they are exactly the array-of-const-declared-second ones; the ctor rows assert a SUM because a count cannot fail a stride bug. TWO RESIDUALS, separately filed and NOT this bug reopening: element-type ranking between two non-const arrays (that one really does need the probe), and a set candidate at the slot, where fpc picks the set and we pick the array -- found by diffing a must-not-move control against fpc and pinned as a guard row whose expected value is pxx's own. Gate GREEN."
---

# Two array parameters at one bracket slot are decided by declaration order

- **Type:** bug (compat) — **Track P** (`compiler/pasparser_call.inc`).
- Found while measuring the controls for the fix that landed as `f00d3d230`,
  *"a bracket argument turned off method overload selection entirely"*. **That
  fix carries no ticket** — it went straight in — so the wiki-link that used to
  stand here resolved to nothing and advertised finished work as a pending
  dependency. De-linked deliberately; the commit is the record.

## The repro

```pascal
{$mode objfpc}
type TC = class
  procedure P2(N: Integer; A: array of Integer); overload;
  procedure P2(N: Integer; A: array of const); overload;
end;
...
c.P2(2, [7, 8]);
```

| | |
| --- | --- |
| fpc 3.2.2 `-Mobjfpc` | `vr n=2 cnt=2` — the `array of const` body |
| pxx at `f00d3d230` | `ints n=2 cnt=2` — the `array of Integer` body |
| pin v405 | `ints n=2 cnt=2` — **pre-existing, not a regression** |

Reversing the declaration order changes which body pxx runs. That is the tell:
nothing about the argument is being consulted.

## Why it is not fixed in `f00d3d230`

That commit made `ArgListHasBracketElem` return a mask of the bracket SLOTS and
narrowed the candidates on them. With **one** array candidate at the slot the
answer is unambiguous and it is taken. With two, the narrowing declines and
falls through to the arity path unchanged, on purpose:
`FindUMethOverloadAhead`'s probe parses arguments speculatively to learn their
types and **cannot parse a bracket argument at all** — no parameter to bind
against, so `ParseArgExpr` reads the `[` as a set literal and `Error` halts.
It therefore has no element type to rank `array of Integer` against
`array of const` with. Picking one anyway would be a guess wearing the shape of
a decision, and the failure mode is a silently wrong body either way.

Unblocking this needs the probe to become parameter-aware, which is the
residual of
[[refactor-p-the-overload-probe-cannot-see-the-argument-match-channels]]
(`done`, but its own summary says the `TypesCompatible` widening was not done).

## Is fpc even right here?

Unclear, and it matters for the prio rather than for the diagnosis. `[7, 8]` is
two integers and `array of Integer` is the closer fit by any element-type
reading; fpc prefers `array of const` regardless. **No real source is known
that wants either answer** — this shape came out of a control I wrote, not out
of a corpus. Rank it when something real asks for it; what must not happen is
someone re-deriving the boundary from scratch, which is why the rows above are
here.

Note the neighbouring case, which is NOT this one and is settled: a `tySet`
parameter at a bracket slot vetoes the narrowing outright, because there the
`[...]` really may be a set. fpc calls `M(1, ['a'])` against
`M(N: Integer; S: TCh)` / `M(N: Integer; A: array of const)` **ambiguous and
refuses it**; we accept it as the set. Us accepting what fpc rejects is not a
defect.

## Gate

`make compiler/pascal26`, the repro above matching fpc, plus
`tools/run_fgl_corpus.sh` 7/7 and `tools/run_pascal_conformance.sh` 391/0 —
the two rows that catch an overload-selection regression; quick alone does not.


## The same property exists on the CONSTRUCTOR path (frankB, 2026-09-06)

Widening this ticket rather than filing beside it, because it is one property
with two addresses.

`ClassCtorArraySigAt` (`pasparser_call.inc`, new at `1c8a6cfd5`) scans a class's
constructors for one whose parameter at the bracket slot is an array, and
**takes the first**. So

```pascal
type TC = class
  constructor Create(const A: array of Integer); overload;
  constructor Create(const A: array of const); overload;
end;
```

decides how `TC.Create([7, 8])` is PARSED by declaration order, exactly as the
method case decides which body runs by it. It has the same cause and the same
reason for not being fixed: **the bracket must be parsed before overload
resolution can run**, so at the moment of the decision there is nothing to rank
the candidates by. The predicate it replaced (`ClassCtorWantsVarRecAt`) had the
same first-match behaviour and additionally always answered TVarRec, which WAS a
defect and is fixed; the ordering is not.

Noting it here so that whoever makes the probe parameter-aware knows there are
two call sites to satisfy and not one, and so that nobody re-derives the
constructor half from scratch.

**Still no real source wanting either answer**, on either path. That is the
prio, and it has not moved.


## Claimed and released without work (2026-09-09, frankS)

Recorded so the next reader does not spend the same twenty minutes: I claimed
this, read it, and put it back **because the ticket is already right about
itself**.

*"No real source is known that wants either answer — this shape came out of a
control I wrote, not out of a corpus."* That is CLAUDE.md's own test (`ON PAR
WITH THE LANGUAGE, NOT WITH FPC`) applied by the ticket's author to the ticket,
and working it would be chasing fpc on a shape nobody writes. The cost is not
small either: the residual is making `FindUMethOverloadAhead`'s speculative
probe parameter-aware enough to parse a bracket argument, and I checked — **this
is that limitation's only open consumer.**

So the group is one ticket wide and its value is the record, not the fix.
**Re-rank it upward when real source asks**, which is what the body already
says; do not take it because it looks like a bug with a clean repro, which is
exactly how it reads from the queue.

## Fixed (2026-09-09, frankS) — and the release above was wrong about WHY

I released this ticket a few hours earlier on the section above, and that
reasoning had one false step. It is worth writing down because the false step is
the ticket's own, repeated in three places and by two authors.

**"The probe cannot parse a bracket, so there is nothing to rank the candidates
by."** True, and it rules out ranking by the ARGUMENT. It does not rule out
ranking at all — and **fpc's actual rule uses no argument.** `array of const`
takes a bracket slot unconditionally. That is a property of the PARAMETERS, and
the parameters are sitting right there in `Procs[]` at the moment of the
decision.

The release also inherited *"no real source is known that wants either answer"*
from the body. That is still true of the ELEMENT-TYPE half. It is not true of
this half: `array of const` beside a typed array is what a formatting or logging
API declares, and the ctor case is worse than a wrong body — it decides how the
bracket is PARSED, so an `array of const` constructor declared second was
receiving an Integer vector.

### Measured before implementing

fpc 3.2.2, both declaration orders, `array of const` against `array of
Integer`, `array of string`, `array of Double` and `array of Byte`, with element
lists of integers, strings, floats and an empty `[]`. **Array-of-const wins
every row**, including rows whose elements cannot convert to the other
candidate's element type. Nothing about the literal is consulted.

### The fix, at both addresses this ticket covers

- **Method** — `FindUMethOverloadAhead` (`compiler/pasparser_call.inc`). The
  bracket-narrowing block already counted array candidates at the slot and took
  the answer when exactly one survived; it now also counts the `array of const`
  ones (`nVR`/`vrOnly`, via `ParamIsVarRecArrayAt`) and takes that when exactly
  one survives, after the existing `nBr = 1` exit and **behind the same veto**.
- **Constructor** — `ClassCtorArraySigAt` (same file), the half frankB added to
  this ticket on 2026-09-06. Two passes: an `array of const` at the slot first,
  then the old first-match. Measured before: `TC.Create([10, 20, 30])` with the
  Integer arm declared first ran the Integer body (`sum=60`) where fpc runs the
  varrec one; after: both orders print `vr cnt=3`, as fpc does.
- `ParamIsVarRecArrayAt` forward-declared in `compiler/frontend_forwards.inc`.

The **veto is untouched and deliberately so**: a `tySet` parameter at the slot
still declines the narrowing outright, for the reason the veto's own comment
gives — the `[...]` really may be a set, and guessing the other way would break
a working call to buy this one.

### Fixture

`test/test_p_an_array_of_const_wins_a_bracket_argument` (Makefile
`test_arrconstwin26`, in `test-core`), 12 rows, **every family declared in both
orders** — a one-order fixture cannot fail this bug, because first-declared is
right half the time by construction. Against the pinned pre-fix compiler exactly
**5 of the 12 move**, and they are exactly the rows declaring `array of const`
second. The constructor rows assert a **SUM**, not a count: a count reads the
same whether the bracket was parsed with an Integer stride or a TVarRec one, so
it cannot fail the defect this half actually has.

**One row of the `.expected` is pxx's own output and not fpc's**, labelled
loudly in the fixture header — see the residual below.

### What is NOT closed, and it is why this is not the whole mechanism

- **Two NON-const arrays differing only in element type.** fpc ranks by element
  (`[7, 8]` takes `array of Integer` over `array of string` in both orders); we
  cannot, and that genuinely needs the parameter-aware probe this ticket
  originally named. Also measured: pxx **refuses** one of those two orders
  outright (`incompatible types: cannot assign Integer to AnsiString`), and the
  PINNED compiler refuses it identically — pre-existing, not caused here.
  → [[bug-p-two-non-const-array-overloads-at-a-bracket-slot-cannot-be-ranked-by-element-type]]
- **A set candidate at the slot.** Found by keeping the veto path in the fixture
  as a must-not-move control and diffing it against fpc anyway: with `array of
  Integer` and `set of Byte` visible, fpc picks the SET and we pick the array.
  The control was expected to be inert and was a divergence.
  → [[bug-p-a-set-candidate-at-a-bracket-slot-vetoes-the-narrowing-instead-of-winning-it]]

So this closes the ticket's stated repro and both of its addresses, and hands
off the part that really does need the probe. **Do not read the two residuals as
this bug reopening**: they are separately measured, separately ranked, and one
of them is pinned by a guard row so it cannot move silently.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 231ac5795.

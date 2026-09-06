---
slug: bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list
track: P
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "A class body recognises `class` only through a hand-maintained lookahead list -- `class const` (pasparser_decl.inc:6772), `class var` (:6796), `class property` (:6808), `class procedure`/`class function` (:6828) -- and every other `class X` spelling falls past all four to the member-loop terminus. It worked because the terminus was a bare `else Next` that stepped over the `class` and left something the remaining arms could parse, so FPC's `class generic function` and `class class function` (its generic-class-method spellings) have never had an opener and have always been handled by accident. Narrowing the terminus in 76efae23e turned that accident into two regressions within an hour -- the full suite caught `class generic function`, frankS's conformance corpus caught `class class function` in tgenfunc3/tgenfunc4 -- both fixed at 7d263221f by putting tkClass back in the skip list, which restores the accident rather than removing it. THE LIST IS THE DEFECT: it is an enumeration that must be extended for every new `class X`, with no diagnostic when it is not, and `class` sitting in a skip list DOCUMENTED as section keywords now hides that. The fix is a tkClass opener that consumes the keyword and re-dispatches, so an unknown `class X` is refused by the arm that owns X."
---

# `class` in a class body is recognised by enumeration, not by structure

```pascal
  if (CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkConst)     then ...  { :6772 }
  if (CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkVar)       then ...  { :6796 }
  if (CurTok.Kind = tkClass) and (Tokens[TokPos].Kind = tkProperty)  then ...  { :6808 }
  if (CurTok.Kind = tkClass) and ((Tokens[TokPos].Kind = tkProcedure)
                              or  (Tokens[TokPos].Kind = tkFunction)) then ... { :6828 }
```

Four spellings, each a separate `tkClass` + one-token lookahead. Anything else
beginning with `class` matches none of them and reaches the member-loop
terminus.

## Why nobody noticed

The terminus was a bare `else Next;`. It stepped over the `class`, and what
remained was usually parseable by the ordinary arms — `class generic function
Foo<T>` becomes `generic function Foo<T>`, `class class function Foo<T>`
becomes `class function Foo<T>` and matches :6828 on the second pass. **The
construct worked, and no arm claimed it.**

That is a working-by-accident that reads as working-by-design from every angle
except this one, and the accident is load-bearing for at least FPC's two
generic-class-method spellings.

## How it surfaced

`76efae23e` narrowed the terminus to a small allow-list and errored on the rest.
Within an hour:

| spelling | found by |
| --- | --- |
| `class generic function` | `make test`, via `test/generic_xunit_method_units/uxgm.pas:10` |
| `class class function` | frankS's conformance corpus, `tgenfunc3.pp` / `tgenfunc4.pp`, 389/0/111 → 387/2/111 |

Both fixed at `7d263221f` by returning `tkClass` to the skip list. **That
restores the accident; it does not remove it.** A third spelling — anything
FPC adds, or that the corpus has and neither instrument reached — is still
silently absorbed today.

## Why this is worth a ticket rather than a shrug

It is the enumerated-predicate shape: a hand-maintained list that must be
extended for every new member of a concept, with **no diagnostic when it is
not**. The list reads as a specification and is really a changelog of what
somebody hit.

It is now actively worse than before, in one specific way. `class` sits in a
skip list whose comment calls it a section keyword alongside `var`. That is the
flattering reading. The true one is that the lookahead list above is incomplete
and the terminus is absorbing its remainder — and the comment I wrote makes the
next reader less likely to find that.

## The fix

A `tkClass` opener that consumes the keyword and re-dispatches into the member
loop, so `class X` is refused by whichever arm owns `X` — and an unknown `X` is
refused with a message naming it, instead of being stepped over. That deletes
four lookahead conditions rather than adding a fifth.

Check before writing it: `class` must remain legal in a RECORD body's skip list
for the same reason it arrives there (records have no class-member arms at
all), so this is a class-body change only unless the record side grows the same
openers.

## Aperture

Neither instrument that caught these was the one I built. My own census swept
`find test lib/rtl lib/pcl`, compiling each file standalone — and pxx cannot
compile a unit standalone, so every construct living only in a unit was
invisible; `library_candidates/fpc-testsuite/` was not in the population at all.
`class` measured 0 fires of 6287. **Any claim here about which `class X`
spellings exist should be read as "the ones two instruments happened to reach",
not as an enumeration.**

## 2026-09-06 — the corpus census that was missing, and it was not a zero

`library_candidates/fpc-testsuite/` has now been run through the catch-all
probe. **`processed=2294  compiled=803  refused=1491  fires=12`** — and the
refused column is the point: 1491 files never reached the probe (`{ %FAIL }`
rows by design, plus units, which pxx cannot compile standalone), so this is
**twelve fires over the 803 files the probe actually read**, not over 2294.

Twelve fires, four files, three token kinds — and **`tkClass` is not among
them**, in this population either:

| file | kinds | source |
| --- | --- | --- |
| `tclass13c.pp` | `tkDot`, `tkInteger_T` | `Value: TRootClass.Integer;` |
| `tclass13d.pp` | `tkDot` | `V2: Integer = TObj.Val;` |
| `trtti12.pp`, `trtti16.pp` | `tkLt`, `tkInteger_T`, `tkGt` ×2 | `A: TArray<byte>;` |

**Not one of them argues for widening the allow-list**, and the reason is the
finding. They are `X.Y` and `X<Y>` — a qualified name and a generic
specialisation — arriving from three different sub-parsers in three different
positions (a field's TYPE, a class-const's INITIALIZER EXPRESSION, a field's
type again), each of which stopped after `X` and left the continuation
unconsumed. **The terminus is not a member-recognition arm; it is where
unclaimed tokens go**, which is precisely why an incomplete lookahead list
above it could stay incomplete for years.

`tclass13c.pp` is a `{ %fail }` row FPC rejects, and the probe build — which is
behaviourally the pre-`76efae23e` terminus — **accepts** it, discarding
`.Integer` and typing the field `TRootClass`. The narrowing makes pxx refuse
it. That is a parity gain, not a cost.

Split out as
[[bug-p-a-generic-specialisation-suffix-on-an-unknown-name-is-dropped-in-field-position]]
for the `TArray<byte>` half. The `TObj.Val` half (a qualified reference to a
class const from inside the same class body) is refused today for an unrelated
downstream reason and is not yet filed.

**What this does NOT establish.** Twelve fires over 803 reachable files says
nothing about the 1491, and the `class X` question this ticket is about is
*still* answered only by "the spellings two instruments happened to reach".
A census cannot enumerate a lookahead list's missing members; only replacing the
list with an opener can.


## 2026-09-06 — measured before restructuring: the accident is not producing a wrong answer today (frankB, Group 23)

Tree at `48a18d6ec`, compiler `b85745ae61a3`, fpc 3.2.2 `-Mobjfpc`. Measured
because the ticket argues from fragility and I wanted to know what the fragility
is currently COSTING, which changes how the fix should be judged.

### The four rows that matter, and only one differs

| row | pxx | fpc |
| --- | --- | --- |
| `generic class function` called via the CLASS | ok | ok |
| `generic class function` called via an INSTANCE | ok | ok |
| **`generic function` (instance) called via the CLASS** | **ok** | **refused** |
| `generic function` (instance) called via an INSTANCE | ok | ok |

### …and the one that differs is us being MORE permissive, safely

The third row is only accepted while the body never touches `Self`. Add a field
read and pxx refuses it — `cannot call non-static method` — so the check exists
and fires exactly when `Self` would be needed. fpc refuses earlier, on the
declaration's staticness rather than on the body's use of it.

**That is "us accepting what FPC rejects", which CLAUDE.md says is not a
defect**, and the acceptance is safe by construction rather than by luck: the
only programs it admits are ones in which `Self` is unobservable. So the
`class X` accident is not currently producing a wrong value anywhere I can
reach.

**Two spellings, and they are not the same one.** FPC's testsuite writes
`generic class function` (tgenfunc3.pp); our own `test/generic_xunit_method_units/uxgm.pas`
writes `class generic function`, which **fpc 3.2.2 refuses outright**
(`Procedure or Function expected`). `GenericKwAt` in `pasparser_generic.inc`
already handles both orders deliberately, with a three-step bound and a written
reason — a loop would eat the class DECLARATION's own `class` when a generic
method is the first member.

### What this does and does not change about the fix

It does **not** weaken the ticket: the list is still an enumeration that must be
extended for every new `class X`, with no diagnostic when it is not, and frankD's
two censuses cannot answer whether a spelling is missing — `find test lib/rtl
lib/pcl` compiled standalone reported `class` at 0 of 6287 because pxx refuses a
unit standalone, and the fpc-testsuite re-census was `processed=2294
compiled=803 refused=1491 fires=12` with `tkClass` not among the twelve. **Two
instruments, 1491 files that never reached the probe, and anything found by
neither would look exactly like this.** "We do not know" is the number.

It **does** change the ranking argument: this is regression PREVENTION, not a
live wrong answer, and it should be judged as such rather than on a defect it is
not currently causing. The value is that the next `class X` spelling either
finds its arm or is refused by name — instead of falling through a `Next` and
working, or not working, by accident.

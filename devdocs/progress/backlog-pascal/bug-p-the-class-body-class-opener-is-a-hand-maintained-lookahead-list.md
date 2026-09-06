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

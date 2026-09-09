---
track: P
prio: 20
type: bug
status: done
owner: frankS
created: 2026-09-09
found-by: frankS
tags: [overload, arrays, probe]
blocked-by: []
summary: "FIXED 2026-09-09. THE BLOCKER THIS TICKET NAMED WAS THE WRONG ONE. It said the overload probe cannot rank two plain array overloads because it cannot PARSE a `[...]` -- true, and it does not matter: fpc ranks by the elements' CLASS, and a class is readable from the TOKENS. `BracketArgElemClass` classifies the bracketed argument (all-integer-literal, numeric with a float, all-string, all-one-char, or UNKNOWN for anything that is not exactly one literal per element) and `BracketCandRank` scores each candidate's element type against it; ranking decides only when exactly one candidate scores best, and a tie or an UNKNOWN falls through to the arity behaviour unchanged. THE HALF THAT MATTERED WAS NOT A WRONG PICK BUT A REFUSAL OF LEGAL CODE: with `array of string` declared first, `c.P(1, [7, 8])` was `incompatible types: cannot assign Integer to AnsiString`, in the pinned compiler too, where fpc compiles it and runs the Integer body. Measured against fpc 3.2.2 with a 72-row matrix (six candidate pairs x six element lists x BOTH declaration orders): differences fell 52 -> 38, and every remaining one is either the tySet case ([[bug-p-a-set-candidate-at-a-bracket-slot-vetoes-the-narrowing-instead-of-winning-it]], out of scope because it changes how the argument is PARSED) or a row where fpc REFUSES and we accept, which is not a defect. Fixture test_p_a_bracket_slot_is_ranked_by_what_its_elements_are, 14 rows, every shape in both orders, fpc's output verbatim; POSITIVE CONTROL VERIFIED -- the pinned compiler refuses the file outright."
---

# Two non-const array overloads at a bracket slot cannot be ranked by element type

```pascal
procedure P2(N: Integer; A: array of Integer); overload;
procedure P2(N: Integer; A: array of string);  overload;
...
c.P2(2, [7, 8]);
```

| declaration order | fpc 3.2.2 | pxx | pinned |
| --- | --- | --- | --- |
| Integer first | Integer body | Integer body | Integer body |
| **string first** | **Integer body** | **refused** | **refused** |

pxx's refusal is `incompatible types: cannot assign Integer to AnsiString`, at
the call line, in both the current and the pinned compiler.

## The blocker, unchanged and now narrower

`FindUMethOverloadAhead`'s speculative probe cannot parse a bracket argument:
there is no parameter to bind against, so `ParseArgExpr` reads the `[` as a set
literal and `Error` halts. With no element types there is nothing to rank
`array of Integer` against `array of string` with.

**What the parent ticket has now shown is how much of it did NOT need that.**
The `array of const` preference is a rule about the PARAMETER — fpc takes it
even for element lists that could not convert to the other candidate, and even
for an empty `[]` — so it was answerable with no argument types at all, and it
covers the case real code actually hits. What is left here is the part that
genuinely needs the probe.

## Resolution, 2026-09-09 (frankS)

### The blocker named an input, not an answer — again

This ticket and its parent both said the probe "cannot rank" because it cannot
parse a bracket. The parent turned out to need no argument at all (`array of
const` wins on a property of the PARAMETER). This one does need the argument —
but it needs its **class**, not its parse, and a class is three token kinds.

`BracketArgElemClass(lp, slot)` walks the bracketed argument at token level and
answers ORDINAL / REAL / STRING / CHAR / UNKNOWN. An element counts only if it
is **exactly one literal token**; `[x + 1]`, `[f(y)]`, `[1..5]` and named
constants all answer UNKNOWN, and the caller then behaves exactly as before.
`BracketCandRank(pi, pj, cls)` scores a candidate's element type against the
class, and the narrowing takes the single best score — a tie decides nothing.

### The measured rule, and the two facts the old fall-through could not express

72 rows: six candidate pairs × six element lists × both declaration orders,
fpc 3.2.2.

1. **fpc's answer does not depend on declaration order.** Every pair answered
   identically in both orders. Ours depended on nothing else.
2. **The interesting half is the refusals we emitted, not the bodies we picked.**
   `array of string` first, `c.P(1, [7, 8])` → `incompatible types: cannot
   assign Integer to AnsiString`. Legal code turned away — the pinned compiler
   too, so this is a gap closed rather than a regression repaired. A silently
   wrong body is the milder sibling.

Encoded exactly as measured: ordinal elements prefer a machine-word ordinal
array over a narrower one (fpc takes `array of Integer` over `array of Byte`)
over a float array; real elements take only a float array; string and char
elements take only a string array.

### What is left, and neither is this ticket

| remaining divergence | why it is not here |
| --- | --- |
| a `set of Byte` candidate at the slot | fpc gives the SET the slot for ordinal elements even against `array of Integer`. Matching it changes how the argument is **parsed**, so the veto and `ParamIsVarRecArray` have to move together — [[bug-p-a-set-candidate-at-a-bracket-slot-vetoes-the-narrowing-instead-of-winning-it]] |
| empty `[]` against two array overloads | fpc REFUSES it as ambiguous; we take the first declared. Us accepting what fpc rejects is not a defect |
| elements no candidate can take (`['a']` vs Integer/Double) | fpc refuses; we accept and run something. Same class, and unchanged by this work |

### The fixture, and why both orders

`test/test_p_a_bracket_slot_is_ranked_by_what_its_elements_are.pas`, 14 rows,
every shape written in both declaration orders. One order would pass on whichever
arrangement happens to agree and assert nothing — the same trap the bracket-door
regression this morning was caught by. Bodies print a VALUE (`sum=`, the joined
string), not a count: a count reads the same whichever body ran.

**Positive control, verified rather than assumed:** the pinned compiler refuses
the file at its last row, `incompatible types: cannot assign Double to
AnsiString`. The guard can fail, and it fails on the pre-change compiler for the
defect it is named after.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

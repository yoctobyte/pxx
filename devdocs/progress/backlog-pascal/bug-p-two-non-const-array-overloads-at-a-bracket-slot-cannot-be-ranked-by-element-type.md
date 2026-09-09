---
track: P
prio: 20
type: bug
status: open
owner: ""
created: 2026-09-09
found-by: frankS
tags: [overload, arrays, probe]
blocked-by: []
summary: "THE RESIDUAL of bug-p-two-array-parameters-at-one-bracket-slot-are-decided-by-declaration-order, which is closed at BOTH its addresses -- FindUMethOverloadAhead's bracket narrowing and ClassCtorArraySigAt: `array of const` now wins a bracket slot unconditionally, matching fpc in both declaration orders, and that needed no argument types. Two NON-const arrays differing only in ELEMENT TYPE still cannot be ranked, because that genuinely needs the argument's elements and FindUMethOverloadAhead's probe cannot parse a `[...]` at all -- ParseArgExpr has no parameter to bind against, reads the '[' as a set literal, and Error halts. fpc ranks by element: with `array of Integer` and `array of string` both visible, `c.P2(2, [7, 8])` takes the Integer one in BOTH orders (measured 2026-09-09, fpc 3.2.2). pxx takes the first-declared in one order and REFUSES the other outright -- `incompatible types: cannot assign Integer to AnsiString` -- and the PINNED compiler refuses it identically, so the refusal is pre-existing and is not a regression from the array-of-const fix. Unblocking wants the probe to become parameter-aware, which is a real piece of work and is the same blocker as bug-p-a-set-candidate-at-a-bracket-slot-vetoes-the-narrowing-instead-of-winning-it."
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

---
track: P
prio: 55
type: bug
blocked-by: [bug-p-a-forward-pointer-in-a-class-type-section-is-not-resolved]
status: rejected
owner: frankH
found-by: frankS
created: 2026-09-09
summary: "REJECTED 2026-09-09 -- NOT A REGRESSION, the sign was inverted. The bisect is sound (ad7c03b03 is where the message changes) but the wall moved FORWARD, to the end of the unit. Two measurements: (1) on identical input -- the interface truncated at line 884, the smallest reproducing prefix -- HEAD and pin v407 BOTH fail at :224, so ad7c03b03 cannot have caused it; (2) DrainPendingPtrTargets runs at the unit's closing `end.` (pasparser_prog.inc:2068), so REACHING that diagnostic means the unit parsed COMPLETELY and the line it prints is where the unresolved `^T` was DECLARED. `224 < 2729` compares a declaration site to a stopping point: at 178270aba the parse stopped at 2729 and the drain never ran; at ad7c03b03 it finishes and the drain finally speaks about a declaration 2500 lines earlier. This ticket's own caveat 1 was right and one step short -- 224 is not where it fails AND not where it stopped, because nothing stopped. The latent bug it exposed was real and is fixed (bug-p-a-forward-pointer-in-a-class-type-section-is-not-resolved, frankZ); verified here at binary fba33bdc4855, the driver prints `drv ok`. The residual -- what ad7c03b03 stopped carrying -- is retired with the sign, but the exact construct it unblocked was never identified and the corpus can no longer answer, since it passes either way."
---

# The bisect

| commit | corpus stops at |
| --- | --- |
| `178270aba` | `generics.defaults.pas:2729` — `no overload of Create matches` (the old wall) |
| **`ad7c03b03`** | **`generics.defaults.pas:224`** — `forward type not resolved` |
| `e1808ad71`, `4a602ebb2`, `340175742`, master `4413aca53` | :224, carried forward |

Driver `uses generics.defaults`, flags `-Fu<src> -Fu<src>/inc`, corpus tree hash
`7314f4e13e39f7fd` verified unchanged at every step. Four rebuilds.

## The construct

```pascal
THashFactory = class
private type
  PPEqualityComparerVMT = ^PEqualityComparerVMT;   { reported here }
  PEqualityComparerVMT  = ^TEqualityComparerVMT;
  TEqualityComparerVMT  = packed record ... end;
```

## Two things that must shape the debugging

1. **The reported line is not the failing line.** The forward-type check is
   deferred to the close of the section, so 224 is where the name was used.
   Truncating the unit at line 236 parses the block cleanly on pin AND HEAD —
   something later in the unit decides whether line 225 ever registers.
2. **The construct is refused by the pin too** in a standalone repro (four
   spellings: objfpc/delphi, program/unit). So this commit did not break forward
   pointers; it removed whatever was letting the corpus through a weakness that
   was already there. Fixing the blocker may close this without touching
   `ad7c03b03` at all.

## What is NOT wrong with ad7c03b03

Its own fix is correct and was verified here independently of its author:
`Take(HashIt)` in a method-callee call goes from the segfault a previous attempt
produced to `arg 42`, byte-matching fpc. The residual `Take(Self.HashIt)` is
still refused with `wrong number of parameters` — filed as NOT COVERED when the
original ticket was written, and worth confirming it survived into that ticket's
resolution now that it sits in `done/`.

## Rejected 2026-09-09 — the wall moved FORWARD; the sign was inverted

The bisect is **sound**: `ad7c03b03` is exactly where the message changes. The
**sign is wrong**, and with it the whole framing. Two measurements settle it.

**1. Identical input, both compilers fail at 224.** Binary-searching the
truncation point gives line 884 of the interface as the smallest reproducing
prefix. Compiling that same file with HEAD and with **pin v407**:

```
HEAD -> pascal26:224: forward type not resolved: `PEqualityComparerVMT`
PIN  -> pascal26:224: forward type not resolved: `PEqualityComparerVMT`
```

The pin fails identically. `ad7c03b03` cannot have caused it. This ticket's own
caveat 2 already said a hand-written version of the construct was refused by the
pin — that observation was right and was not carried into the conclusion.

**2. The check runs AFTER the whole unit has parsed.**
`DrainPendingPtrTargets` is called at the unit's closing `end.`
(`pasparser_prog.inc:2068`) — which is also why `ParsingClassBodyCi` is -1 there,
the mechanism of the real bug. So **reaching that diagnostic means the unit
parsed completely**, and the line it prints is where the unresolved `^T` was
**declared**.

**`224 < 2729` compares a declaration site to a stopping point.** At
`178270aba` the parse stopped at 2729 and the drain never ran. At `ad7c03b03`
the parse gets all the way through and the drain finally speaks, about a
declaration 2500 lines earlier. `ad7c03b03` **removed** a wall and exposed a
latent bug that had been unreachable behind it.

This ticket's caveat 1 — *"224 is where it is REPORTED, not where it fails"* —
was correct and one step short: it is also not where anything **stopped**,
because nothing stopped.

### What was really there, and it is fixed

[[bug-p-a-forward-pointer-in-a-class-type-section-is-not-resolved]] — a forward
pointer to a nested plain alias, refused because `AliasVisibleHere` reads
`ParsingClassBodyCi`, which is -1 at drain time. Fixed by frankZ. Verified here
at binary `fba33bdc4855`: the driver compiles and prints `drv ok`, past `:224`
and past the old `:2729`.

### The residual is retired, not parked

*"`ad7c03b03` stopped whatever was carrying the corpus case"* presupposed the
inverted sign and does not survive it. Nothing was removed; a wall was.

**One honest gap, recorded so it is not read as settled:** the exact construct
`ad7c03b03` unblocked was never identified. The pin's own wall
(`System.Integer(ALeft) - System.Integer(ARight)` inside `class function
TCompare.UInt8`) would not reduce — standalone it compiles and prints 5 on the
pin **and** at HEAD. So this says `ad7c03b03` unblocked *enough to finish the
unit*, not *what*. The two measurements above stand without it, and the corpus
can no longer answer the question anyway: it passes either way now.

`rejected/` rather than `done/` because the report itself is wrong — there was
no regression. The bug it surfaced was real, has its own ticket, and is closed.

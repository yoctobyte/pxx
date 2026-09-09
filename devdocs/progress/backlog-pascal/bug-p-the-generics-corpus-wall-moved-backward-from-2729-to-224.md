---
track: P
prio: 55
type: bug
blocked-by: [bug-p-a-forward-pointer-in-a-class-type-section-is-not-resolved]
status: open
owner: frankH
found-by: frankS
created: 2026-09-09
summary: "REGRESSION, bisected to ad7c03b03 (`a bare method name in argument position is referenced, not called`). The rtl-generics corpus wall moved BACKWARD: `178270aba` reaches generics.defaults.pas:2729, `ad7c03b03` stops at :224 with `forward type not resolved: PEqualityComparerVMT`. Same driver, same corpus, corpus tree hash 7314f4e13e39f7fd unchanged throughout; bisected by rebuilding at each commit and re-confirmed at master 4413aca53 / binary 4d1b041a7fc9. Everything later that was tested (e1808ad71, 4a602ebb2, 340175742) carries it, so it is one change and not an accumulation. TWO CAVEATS THAT CHANGE HOW TO DEBUG IT: 224 is where the name is USED and not where the failure is decided -- the check is deferred, and truncating the unit at 236 parses that block cleanly on BOTH pin and HEAD; and a hand-written minimal version of the same construct is refused by pin v407 too, so ad7c03b03 most likely stopped whatever was carrying the corpus case rather than breaking forward types outright. That latent half is [[bug-p-a-forward-pointer-in-a-class-type-section-is-not-resolved]]. The fix in ad7c03b03 is otherwise CORRECT and verified independently: `Take(HashIt)` goes from a segfault to `arg 42`, matching fpc."
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

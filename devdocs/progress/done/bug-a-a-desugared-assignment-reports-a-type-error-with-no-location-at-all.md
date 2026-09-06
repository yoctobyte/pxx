---
track: A
prio: 45
type: bug
blocked-by: []
status: done
owner: frankD
created: 2026-09-06
summary: "`incompatible types: cannot assign Pointer to record` printed as `pascal26:0: error: ...` with NO line, NO `in: <file>` and NO `near:` window — the whole locating apparatus goes silent at once, because all three are driven off the line number and the AN_ASSIGN node carries 0. Every synthesised assignment has this shape: GenMakeAssign is called by ~20 desugarings (free-object temps, for-in, with-temps, string-arg temps) and none of them stamp ASTLine, so the assignment type check added at ir.inc:12163 — which fires on ANY AN_ASSIGN, deliberately, because that is the one funnel every syntactic form passes through — reports its findings against a node the user cannot be shown. THE CHECK IS RIGHT AND ITS COORDINATES ARE ABSENT, which is worse than wrong coordinates only in that nobody can even start. Live: fcl-passrc pastree.pp, 5947 lines, one such error and no way to narrow it. Proposed fix: fall back to the first descendant carrying a nonzero line (a desugaring nearly always clones a real operand), or stamp ASTLine in GenMakeAssign from the parser position."
---

# A desugared assignment reports a type error with no location at all

- **Type:** bug (diagnostics) — **Track A** (`compiler/ir.inc`, `ASTLine`).
- Found in fcl-passrc rung 7, [[feature-pascal-corpus-expansion]].

## The observation

```
pascal26:0: error: incompatible types: cannot assign Pointer to record
```

That is the entire output. No `in: <path>` line, no `near:` token window — and
those are not three independent losses. `ErrorPrintAt` drives all of them from
the line number, so a zero takes the file and the window with it. **The failure
is total rather than partial, which is the only reason it is worth a ticket
instead of a shrug**: a wrong line still lets you look, and this leaves a 5947-line
unit with a real defect in it and no way to narrow.

## Why every desugaring has this shape

The check at `ir.inc:12163` fires on **any** `AN_ASSIGN`, and that breadth is
deliberate and correct — its own comment says so: every syntactic form of
assignment funnels through this node, so one rule covers `for` variables, `+=`,
out-param clears and field stores instead of ~20 sites. The cost of that choice
is that the node is also what ~20 DESUGARINGS build, and `GenMakeAssign` stamps
no line. So the check is reachable from nodes that were never written down.

## Two fixes, and the first is cheap

1. **Fall back to a descendant's line.** A desugaring nearly always clones a
   real operand, which carries a real line. `ASTLineOrDescendant(node)` used at
   the reporting site fixes every caller at once and cannot make a good line
   worse.
2. **Stamp `ASTLine` in `GenMakeAssign`** from the current parser position.
   Better data, more sites, and it is the one that also helps the debugger.

They compose; 1 is the safety net for whatever 2 misses.

## Gate

A program whose only defect is inside a desugared assignment must report a line
in the user's file. **The positive control is the shape, not the message**: any
fixture asserting the error TEXT would already pass today, since the text is
correct — the assertion has to be on the coordinate.


## CORRECTION 2026-09-06, same day, by the author

**The symptom was real and the cause named here was not.** The fix is in
[[bug-a-a-semantic-diagnostic-in-a-used-unit-has-no-location-at-all]].

What this ticket got right: the total failure (line, `in:` and `near:` all
vanish together, because `ErrorPrintAt` drives all three off one number), and
that the AN_ASSIGN check's deliberate breadth is what puts it in reach of nodes
nobody wrote down.

What it got wrong, and how: it proposed **"~20 desugarings build AN_ASSIGN and
`GenMakeAssign` stamps no line"** as the cause. Every clause of that is TRUE.
It is also not what happened — `AllocNode` zeroes `ASTLine` for every node from
an appended unit, hand-written statements included, and the offending statement
in fcl-passrc's pastree.pp was written by a human on line 5817. **A true
mechanism standing next to a real symptom reads as an explanation**, and this
one was never tested: the two-row control that settles it (the identical
statement at line 30 of a program and line 18 of a unit) took one minute and
came after the ticket was filed, not before.

Both of the fixes it proposed would also have been wrong here. Falling back to
a descendant's line finds another line-0 node; stamping `GenMakeAssign` from
the parser position fixes nothing for a node the parser built directly.

Do not read the two fixes as still-open work. Neither is needed.

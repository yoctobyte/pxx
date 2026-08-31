---
track: P
prio: 40
type: refactor
blocked-by: []
summary: "The `bug-p-a-char-array-is-not-a-string-in-any-direction` rule is implemented at FIVE separate sites in ir.inc, each carrying a comment pointing at the others. root-cause-over-microfix calls three copies a design flaw; this is five. Found during the cir.inc inventory, in Pascal's ground, not C's."
status: new
owner: ""
---

# The "a char array is not a string" rule is spelled five times

- **Type:** refactor — **Track P** (the sites are Pascal lowering).
- **Found:** 2026-08-29 by frankC during the `cir.inc` carve-out inventory;
  routed here by the coordinator because it is not Track C's ground.

## The measurement

The rule from `bug-p-a-char-array-is-not-a-string-in-any-direction` appears at
**five** separate sites in `compiler/ir.inc`, each with a comment pointing at the
others. They are Class-B sites in the carve-out inventory — `not CProgramMode`
guards around **Pascal** code, so they are Pascal's to consolidate.

`devdocs/dev/root-cause-over-microfix.md` sets the line explicitly: *"count how
many mechanisms serve the one concept (two is a smell, three is a design
flaw)."* This is five, and the cross-referencing comments are evidence that each
author knew about the others and added a sixth spelling anyway rather than
consolidating — which is the failure mode that document exists to name.

## Why it is filed rather than fixed

frankC found it while inventorying `ir.inc` for the C carve-out and correctly did
not touch it: these sites are Pascal lowering behind a C guard, not C lowering.
Moving them would have relocated part of the Pascal frontend into `cir.inc`.

## What to do

Consolidate to one predicate. Per `normalise-dont-special-case`, the win is
deleting cases rather than adding a sixth; and per
`root-cause-over-microfix`, **measure by tickets-closed-per-change** — check
whether the open char-array tickets collapse onto the single implementation
before deciding scope.

**Grep for the sibling before closing:** five copies means a fix on one arm is
the default outcome, not the risk.

## Related

Coordination context and the full Class-A/B/C inventory:
`refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed`.

---
track: A
prio: 60
type: bug
blocked-by: []
summary: "An {$I} directive inside an included file was left in the text instead of expanded, and the lexer then skipped it as an unknown directive — so every declaration in the nested file silently vanished and a DIFFERENT program compiled than FPC builds from the same source. Expansion now recurses, resolving each step against its own file's directory, with a depth brake for circular includes."
status: done
owner: claude-acp
---

# A nested include is silently dropped

- **Track A** (`compiler/elfwriter.inc` `ExpandIncludes`, `compiler/defs.inc`).
- Found while carving `parser.inc` apart for
  [[refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files]] — the first
  slice was included from `parser.inc` and simply did not appear.

## Symptom

```pascal
{$I outer.inc}      { outer.inc contains: {$I inner.inc} }
```

Everything declared in `inner.inc` is undefined. No diagnostic names the
include; the error surfaces far away, at the first *use*:

```
pascal26:116119: error: undefined variable (DetectPascalRuntimeNeeds)
```

FPC compiles the same three files and prints `l1 l2 l3`. This is not a missing
feature that fails loudly — it is **silent divergence from the reference
implementation**, the shape the compat rules say to promote to a `bug-` ticket
rather than file as parity work.

## Root cause

`ExpandIncludes` (`elfwriter.inc`) said so in its own header comment: *"Replace
active dollar-include directives with file contents, **one level deep**."* It
scans `src` and appends to `IncExpanded`, but never scans the text it splices
in. A directive inside that text therefore survives into the real lexer pass,
where an unrecognised `{$...}` is skipped like a comment.

The one-level limit was invisible because **no `.inc` in the compiler included
another `.inc`** — 58 files, and the shape had never been exercised in-tree.
User code hits it immediately: nested includes are ordinary Pascal.

## Fix

Recursion, not a re-scan of the result. Both were available; the re-scan is
wrong because of `-g`: the line markers name the file a line came from, and a
second pass over already-spliced text attributes the inner file's lines to the
outer one. Recursing lets each file emit its own markers, and the existing
`IncEmitLineMarker(fullPath, 1)` / `IncEmitLineMarker(selfPath, markLine)` pair
around the splice then bracket the inner text correctly with no change.

The catch is that `IncExpanded` / `IncIncluded` are module-level buffers, not
locals, and the callee does `SetLength(IncExpanded, 0)` — so the splice site
hands the recursive call copies and puts its own accumulator back afterwards.

Each nesting step resolves relative to **its own** file's directory (derived
from the already-normalized `fullPath`), which is what FPC does and what makes a
bare `{$I sibling.inc}` inside a subdirectory work.

`MAX_INC_DEPTH = 32` is the brake circular includes need (FPC's own limit is
16). Two files that include each other are a legal thing to write and an
infinite thing to expand; it now errors instead of exhausting the stack.

Conditional handling is unchanged and gets the nesting for free: the recursive
call simulates the inner file's own `{$ifdef}`s, so an include in a dead branch
is never opened.

## The bootstrap constraint this exposed (worth knowing before the next carve-out)

`make compiler/pascal26` compiles `compiler.pas` with the **pinned** binary. So
the compiler's own source cannot use a feature the pinned binary lacks, and
this fix does not become usable *in-tree* until a compiler carrying it is
pinned. The `parser.inc` carve-out therefore lists its slices flat in
`compiler.pas` rather than nesting them under `parser.inc` — which also matches
how every other frontend is spelled there.

## Tests

- `test/test_nested_include.pas` — **three** levels, because a fix that merely
  added a second level would pass a two-level test. Level 2 sits in a
  subdirectory and includes level 3 by bare name, so it resolves only if each
  step searches its own directory; a dead `{$ifdef}` in level 2 includes a file
  that does not exist, asserting inactive branches are not opened; and a
  `{$define}` in level 3 is observed at program level, matching FPC.
  Verified against the FPC oracle (identical output); the pinned binary fails
  with `undefined variable (NEST_L2)`, so the test bites.
- `test/test_include_cycle_fails.pas` — mutually-including files must give a
  diagnostic and a non-zero exit, not a hang.

## Gate

`make compiler/pascal26` (byte-identical self-host fixedpoint) + both tests
against the FPC oracle + `tools/gate.sh quick` GREEN.

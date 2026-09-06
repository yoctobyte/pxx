---
slug: bug-p-the-conditional-evaluator-cannot-answer-sizeof-so-eleven-corpus-rows-die-in-the-preprocessor
track: P
type: bug
prio: 40
status: backlog
owner: ""
created: 2026-09-06
found-by: frankS (measured), filed by frank-coordinator
blocked-by: []
title: "`{$if sizeof(Extended) <> sizeof(Double)}` is unanswerable, so eleven helper-suite rows fail before any helper is parsed"
summary: "The Pascal conditional evaluator in `paslexer.inc` has no `sizeof` operand, so `{$if sizeof(Extended) <> sizeof(Double)}` cannot be evaluated and the file dies in the PREPROCESSOR. Measured by frankS 2026-09-06 over the full 1362-file FPC suite (NOT the curated 550): the helper families `tchlp`/`trhlp`/`thlp`/`tthlp` are 182 files, 68 pass, 113 fail — the largest single cluster in the corpus — and ELEVEN of those 113 die here, with no helper construct involved at all. SIXTH INSTANCE of a partition-labelled row naming a defect that has nothing to do with the partition, so do not read `113 helper failures` as 113 helper defects. THE FIX HAS A REAL CONSTRAINT AND IT IS THE WHOLE TICKET: `{$include paslexer.inc}` is at `compiler/compiler.pas:69` and `{$include symtab.inc}` is at `:132`, so a size table written into `paslexer.inc` would be a SECOND SOURCE OF SIZE TRUTH, which is the defect this repo keeps paying for. The shape that works is a forward-declared `PasCondSizeOfTypeName` with its body beside the type table, matching the forward-declaration block that already sits immediately above `{$include lexer.inc}` in `compiler.pas` and exists for exactly this ordering problem."
---

# Filed 2026-09-06 — frankS measured it, this seat filed it; neither holds it

## What fails

`{$if sizeof(Extended) <> sizeof(Double)}` — an ordinary FPC idiom for guarding a
platform-dependent arm. The conditional evaluator (`PasCond*` in `paslexer.inc`,
`PasCondOpPrecedence` and friends) understands `!`, `&`, `|` and comparisons over defined
symbols and integers. **It has no `sizeof` operand**, so the directive cannot be answered
and the file stops before the program is reached.

Verified in this tree 2026-09-06: `grep -n sizeof compiler/paslexer.inc` returns three hits
and **all three are prose inside comments**. There is no handler.

## Why the count is the interesting part, and why it is not a helper bug

frankS ran the FULL suite (`--all`, 1362 top-level `.pp`), not the curated 550 the default
invocation uses — **the two numbers are not comparable and this one is only about the wide
set.** In it:

| family | files | pass | fail |
| --- | --- | --- | --- |
| `tchlp` `trhlp` `thlp` `tthlp` | 182 | 68 | 113 |

**Eleven of the 113 die in the preprocessor with no helper involved.** A row's family name
records the ROW's subject, never the DEFECT's — this is the sixth recorded instance of that
in this corpus, so `113 helper failures` must not be read as 113 helper defects, and closing
this ticket will move the helper number without touching helpers.

## THE CONSTRAINT — read this before writing the fix

`compiler/compiler.pas`:

```
 68  {$include lexer.inc}
 69  {$include paslexer.inc}
132  {$include symtab.inc}
```

The type table lives on the far side of that gap. **A size table added to `paslexer.inc` would
be a second source of size truth**, which is the mechanism behind
`refactor-a-the-const-cast-width-table-is-the-third-copy` and its family — and the copies
diverge on exactly the targets nobody measures on.

The shape frankS names, and it is the one the file already uses for this problem: a
**forward-declared `PasCondSizeOfTypeName`**, body beside the type table, matching the
forward-declaration block that sits immediately above `{$include lexer.inc}` — a block whose
own comments say it exists because `lexer.inc` is included before the units that own the
answers (`DbgFileId`, `MarkUnitPxxDialect`, `TargetHasSignalRuntime` are all that pattern).

## What is NOT established

- Whether the other 102 helper failures share a cause; frankS did not cluster them.
- Whether any curated-550 row hits this. The eleven are in the wide set only, so this may
  move no number the default runner prints.
- Which types the evaluator would need beyond `Extended` and `Double`.

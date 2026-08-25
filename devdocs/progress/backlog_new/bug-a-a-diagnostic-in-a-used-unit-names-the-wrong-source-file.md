---
slug: bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file
title: "The `in: <path>` line under an error can name a file that does not have that many lines"
track: A
prio: 40
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Compiling a program with nested `uses`, an error at generics.defaults.pas:2074 printed `in: lib/rtl/platform.pas` — a 707-line file. The token→file map is a start-only range list scanned backwards, which assumes token index rises monotonically with source file; nested unit parsing does not honour that. Costs real time when chasing a wall through a corpus unit."
---

# Measured, 2026-08-25 (HEAD)

```
$ pascal26 -Fu. -Fuinc gd.pp out
pascal26:2074: error: undefined variable (New)
  in: /home/neo/frank1/compiler/../lib/rtl/platform.pas
  near: PSpoofInterfacedTypeSizeObject  begin Result  New >>>  PSpoofInterfacedTypeSizeObject
```

`lib/rtl/platform.pas` is **707 lines long**, so line 2074 cannot be in it. The
`near:` window is the giveaway: that text is `generics.defaults.pas:2074`, which
is where the error actually is. The line NUMBER is right and the FILE is wrong —
the worst combination, because the number lends the wrong file credibility.

# Suspected mechanism (NOT yet confirmed — measure before fixing)

`WriteDiagSourceFile` (`compiler/lexer.inc`) asks `PasSrcOfTok`
(`compiler/dbg_filetable.inc`), which keeps a **start-only** range list
(`PasSrcRangeStart` / `PasSrcRangeId`) and scans it BACKWARD for the last range
whose start is `<= t`. That is only correct if the list is sorted by start, i.e.
if a token's index rises monotonically with the file it came from. Marks are
planted at lex time, so within one lexing pass it holds; what has not been
checked is whether nested `uses` resolution can plant them out of order, or
whether `TokPos` at diagnosis time points into a different pass's range than the
LINE the error carries.

Two things to measure before touching anything, in this order:

1. dump `PasSrcRangeStart[]` for the failing compile and check it is sorted;
2. print the `t` that `WriteDiagSourceFile` computes alongside the line the
   error carries, and see whether they even come from the same pass.

If the list is sorted and `t` is right, the bug is elsewhere and this ticket's
guess is wrong — say so in the resolution rather than fixing the guess.

# Why it is worth fixing

Every corpus-driving session (`feature-pascal-corpus-generics`,
`feature-pascal-corpus-*`) reads exactly this line to find out WHERE the wall
is. A wrong answer sends the reader to a file that does not contain the
construct, and the reader's first instinct is to doubt the line number too.

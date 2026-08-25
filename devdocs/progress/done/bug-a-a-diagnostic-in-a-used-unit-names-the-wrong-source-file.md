---
slug: bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file
title: "The `in: <path>` line under an error can name a file that does not have that many lines"
track: A
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
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

# Resolution 2026-08-25 — and BOTH guesses above were wrong

The two things this ticket said to measure were measured, and neither was the
cause. Recording that, because the shape repeats: the range list **is** sorted,
every mark **is** planted at the right index (`Lexing=TRUE`, `startTok =
TokCount`, one per unit, in lex order), and the token index the diagnostic asks
about **is** the right token — `tok=60431 srcline=2082` was exactly the
`OrdType` token. Everything the ticket proposed to check was healthy.

## What it actually was

The map is keyed on **absolute token indices**, and the token stream is EDITED
after the marks are planted. `InsertTokens` / `RemoveTokens` already kept the
body pass's spans in step (`AdjustPass2Spans`) and nobody had ever extended that
to the file ranges — but the edit that matters here does not even go through
them. **The generic-specialization splice hand-rolls its own insert** at
`TokPos` (`compiler/pasparser_generic.inc`, the `Inc(TokCount, subCount)` at the
end of the substitution loop) and adjusts nothing at all. Generics.Defaults
specializes heavily, so its stream grew by **~28,000 tokens** — every file
boundary above the splice then sat tens of thousands of tokens too low, pointing
deep inside the corpus unit while still carrying the next unit's name. The
`platform.pas` in the report was simply the range that happened to cover 60431
after the drift.

Two more hand-rolled edits had the same hole: the operator-overload desugar's
named-result excision and its two-token `function <synName>` insert
(`compiler/pasparser_call.inc`).

Measured with the new `PXXDBG=a.srcmap` (see below), which prints the range
table with the source line and TEXT of the tokens on both sides of each
boundary. Before: range `[6] platform.pas` starts at a token reading `System
AnsiChar` at line 1809. After: it starts at `unit platform` at line 2, and the
token before it is line 707 — platform.pas's own last line. That one line of
output is what turned two wrong theories into the right one.

## Fix (landed 2026-08-25)

- New `AdjustSrcRanges(atPos, delta)` in `compiler/dbg_filetable.inc` — twin of
  `AdjustPass2Spans`, moving `PasSrcRangeStart` **and** `DbgRangeStart` (the
  DWARF line table asks the identical question and drifts identically under
  `-g`).
- Called from `InsertTokens`, `RemoveTokens`, the nested-routine lift's shift
  (`pasparser_decl.inc`), the specialization splice (`pasparser_generic.inc`)
  and both operator-desugar edits (`pasparser_call.inc`).
- New `PXXDBG=a.srcmap:*` — the range table, the queried token index, and a
  PLANT line per mark. Documented in `devdocs/dev/debug-switches.md` and
  `devdocs/dev/debugging-playbook.md`.
- Regression test `test/test_diagnostic_names_the_right_unit.pas` +
  `test/srcmap_units/{uspec,uhelper}.pas`, wired into `test-core`. It compiles a
  unit that specializes two generics, `uses` a second unit, and then has one
  deliberate undefined name; the assertion is that the `in:` line names
  `uspec.pas` **and does not mention `uhelper.pas`**. The pinned binary fails it.

## Left open, deliberately

The specialization splice also skips `AdjustPass2Spans`. That may be correct
(`Pass2Active` is likely false while specializing, making it a no-op) or it may
be a second latent bug — but it can change CODEGEN, unlike the range fix, so it
was not touched here on the way past. Someone should settle it:
`bug-a-the-specialization-splice-does-not-adjust-the-body-pass-spans`.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.

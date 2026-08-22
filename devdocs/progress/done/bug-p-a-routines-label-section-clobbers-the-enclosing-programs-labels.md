---
track: P
prio: 60
type: bug
blocked-by: []
status: done
owner: claude-A
commit: PENDING-COMMIT
summary: "A routine with its own `label` section overwrote the enclosing program's label table — entering a body reset GotoLabelCount to 0 and restored the COUNT on exit but not the slot CONTENTS. The program's own `la:` then failed with `AN_LABEL: undeclared label`. Fixed alongside numeric labels (`label 1;`), which were refused outright."
---

# A routine's label section clobbers the enclosing program's labels

Found 2026-08-22 by an FPC differential sweep over less-trodden language
features. Two independent defects in the same area, fixed together because the
first is what exposed the second.

## Defect 1 — a routine's labels overwrite the program's

```pascal
program p;
label la, done;
procedure Q;
label lq;                 { <-- this }
begin ... goto lq; ... end;
begin
la:                       { pascal26: AN_LABEL: undeclared label }
  ...
end.
```

`fpc -Mobjfpc -O1` compiles and runs it. pxx refused it, and refused it just as
hard with **identifier** labels as with numeric ones, so it is not a spelling
problem.

**Root cause.** Entering a routine body did:

```pascal
savedGLC := GotoLabelCount;
GotoLabelCount := 0;          { <-- }
...
GotoLabelCount := savedGLC;   { restores the COUNT, not the CONTENTS }
```

The routine's labels were therefore written into slots 0..n-1 — the slots the
enclosing program had already filled. In a Pascal program the label section
comes first, the routines next, and the main body LAST, so by the time the main
body looked up `la` those slots held the routine's names.

**The fix** is a base index rather than a reset. `GotoLabelBase` marks where the
current routine's labels start; every lookup scans `[GotoLabelBase,
GotoLabelCount)`. A nested routine neither sees nor clobbers the enclosing
scope's labels — and it *should* not see them, since a non-local goto is
illegal in Pascal anyway (still refused; verified).

Six scan sites moved to the base: the two lookups in `ir.inc` (`AN_LABEL`,
`AN_GOTO`), the two fixup-verification loops in `pasparser_proc.inc`, the one in
`pasparser_prog.inc`, and the `GotoLabelIRId` reset, which now clears only
`[base, MAX)` so the enclosing scope's IR ids survive the nested parse.

## Defect 2 — numeric labels were refused

```
program p; label 1; begin 1: WriteLn('x'); end.
    pascal26: Expected: begin, but got:  (Kind: 2)
```

Three sites accepted `tkIdent` only: the label section, the `n:` statement
position (a number never reached the `tkIdent` case that handles a label
definition), and `goto n`.

**Root cause of the awkward part.** Labels are matched by SPAN, over the token
char pool (`TokSlicesMatch`), which works because the lexer copies every token's
`SVal` there. A `tkInteger` token has **no `SVal` at all** — the value lives in
`IVal` — so its span is zero-length and every numeric label would have matched
every other one. `LabelSpanOfTok` therefore synthesises the span from the VALUE
via `AIntToStr`, and the whole existing match/fixup machinery works unchanged.

### Known divergence: leading zeros

Synthesising from the value means `007` and `7` are the **same** label here.
FPC keys numeric labels by their source text and rejects `goto 7` against a
declared `007` ("Identifier not found 7"). Ours is the more forgiving rule and
no program that compiles under FPC can observe the difference — a source that
declares `007` and jumps to `7` does not build there at all. Not asserted in the
test; recorded here so a future reader does not read it as an accident.

## Verified against fpc

One program covering both: a numeric label as a backward target and as a
forward target (fixed up later); a routine with its own numeric label declared
*before* the main body — the exact shape that used to clobber; a routine with
identifier labels; three nested scopes (`Shadowing` / its nested `Nested` / the
program) all reusing the label name `m`; and the program's own identifier labels
resolving *after* all of those routines. Output byte-identical to `fpc -O1`.

Non-local goto stays refused (`goto` from a routine to a program label). The
message differs from FPC's, which is deliberate — error reporting is ours by
default (CLAUDE.md).

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
Test `test/test_goto_labels_numeric_and_scoped.pas`, wired into `test-core` with
both a last-line and a line-count assertion so a silently truncated run fails.

---
slug: bug-a-the-near-context-window-is-stale-after-a-token-splice
track: A
prio: 45
type: bug
status: done
blocked-by: []
summary: "FIXED. A token splice shifted `Tokens[]` and left the ten positional arrays beside it unshifted, so every `near:` window past the edit printed the spelling that used to live at that index. `ShiftTokParallel` now moves all ten (all eleven checked against their declarations; every one is positional). The prescribed fix in `InsertTokens`/`RemoveTokens` measured as NO CHANGE -- a specialization never goes through `InsertTokens`, `pasparser_generic.inc` has a second hand-rolled splice, and that is the commit that moved the symptom. A residual followed and is also fixed: zeroing the spelling channel in the gap is right for a SYNTHESIZED token and wrong for the specializer's VERBATIM COPIES, so the window lost its punctuation until the span was carried through the template and specialize pools. 575e71ccf, 95c98db70."
owner: franka-29
---

# The `near:` context window is stale after a token splice

Found while fixing
[[bug-p-a-specialized-body-reports-errors-in-the-wrong-file]]. That bug was the
`in:` FILE; this is the `near:` TEXT, and it is a different mechanism in a
different file, which is why it is filed separately rather than folded in.

## Measured

`test/test_generic_error_location_names_a_third_file_fail.pas`, binary
`a9a4818ab6c8` (i.e. **after** the file-attribution fix):

```
pascal26:22: error: unknown type: TNoSuchTypeAnywhere
  in: test/generic_errloc_units/uerrtmpl.pas      <- correct
  near: < T > = class public >>> Val : T          <- not the error site
```

The line and file are now right — `uerrtmpl.pas:22` is `q: TNoSuchTypeAnywhere;`.
The `near:` window is not.

**The output convicts itself, without reading any code.** The window prints
`< T >` and `: T` — an **un-substituted** type parameter. Substitution rewrites
every `T` in a specialized body before the tokens are spliced, so that text
*cannot* exist in the region the parser was reading. What is printed is text
that lived at those indices before the splice moved everything up.

## Where it comes from

`WriteTokenContext` (`compiler/lexer.inc:653`) prefers the
`TokSrcOff[]`/`TokSrcLen[]` channel — a token's SOURCE SPELLING, added so the
window stops dropping punctuation — and falls back to `Tokens[].SOffset/SLen`
only when `TokSrcLen` is 0.

`InsertTokens` (`compiler/lexer.inc:2896`) shifts `Tokens[]`:

```pascal
  for i := TokCount - 1 downto insertPos do
    Tokens[i + count] := Tokens[i];
  ...
  AdjustSrcRanges(insertPos, count);
```

`TokSrcOff`/`TokSrcLen` are not in that loop, and `RemoveTokens` has the same
shape. So the preferred channel desynchronises from `Tokens[]` at the first
splice and stays that way.

This is the same class of defect as `AdjustSrcRanges` itself, whose comment
already records the lesson: *"a token-stream EDIT at `atPos` moves every token
after it — so it moves the file boundaries too."* It moves the spellings too, and
one parallel array was missed. `EnsureTokCapacity`'s comment makes the same
point from the other side — *"ALL 11 token arrays grow in lockstep — a missed one
is a silent out-of-bounds."*

## Why it matters more than a cosmetic window

`near:` is currently the field corpus triage is told to trust. Two agents
independently used it to locate the real source of a mis-attributed error on the
rtl-generics corpus, precisely because it was the field that looked honest while
`in:` was known-broken. It is honest **until the first splice**, and a
specialization-heavy corpus is nothing but splices. A field that is right in the
simple cases and silently wrong in the hard ones is worse than one that is
obviously broken.

## Not fixed here, and why

`lexer.inc` is shared Track A ground and Track P must not edit it concurrently
with A. The fix is small — shift the two arrays alongside `Tokens[]` in both
`InsertTokens` and `RemoveTokens` — but it belongs to A.

**Check the whole set, not these two arrays.** `EnsureTokCapacity` grows 11
token-parallel arrays; `InsertTokens` shifts one. Enumerate them and decide per
array whether it is positional, rather than fixing the two this ticket happens
to name.

## Gate

An error inside a specialized body whose `near:` window contains the offending
token. The existing
`test/test_generic_error_location_names_a_third_file_fail.pas` is the repro; add
a fourth grep to its recipe in `test-core`:

```
	grep -q "near: .*TNoSuchTypeAnywhere" $(TESTTMP)/test_generic_errloc.log
```

## Resolved — 575e71ccf (the shift) and 95c98db70 (the spelling)

**The ticket's own fix measured as NO CHANGE, and that was the finding.** Wiring
a `ShiftTokParallel(atPos, delta)` helper into `InsertTokens`/`RemoveTokens` --
exactly what "Not fixed here, and why" prescribes -- moved the symptom not at
all. A generic specialization never goes through `InsertTokens`:
`pasparser_generic.inc` carries a second, hand-rolled splice, whose own comment
says it "owes the same bookkeeping". It did not pay it. Both call the helper now.

**All eleven, as asked.** Checked each against its declaration in `defs.inc`:
all ten non-`Tokens` arrays are POSITIONAL -- each documents state *at this
token* -- so every one of them owes the shift, not just the two this ticket
names. `ShiftTokParallel` sits immediately beside `EnsureTokCapacity` so the two
lists are read together; separating them is what let one run ahead of the other.

The gap a splice opens is filled in two ways on purpose: directive state is
lexically continuous and inherits from `atPos-1`, while the spelling channel is
ZEROED, which is right for a SYNTHESIZED token (no source range exists, and the
fallback to `SOffset/SLen` is its text).

**That zero was wrong for the specializer, which is the second commit.** Its
tokens are VERBATIM COPIES of template tokens with real source ranges, and
`SOffset/SLen` holds text only for identifiers and strings -- so the window went
from stale-and-complete to correct-and-punctuationless, reproducing the very
defect `TokSrcOff`/`TokSrcLen` were added to fix, one scope down. The span now
travels with the token through the template and specialize pools, carried for
verbatim copies and zeroed for SUBSTITUTED ones so the fallback prints their new
text -- carrying it there would print the old word one token over.

```
before        near: < T > = class public >>> Val : T
575e71ccf     near: Integer   var q  >>> TNoSuchTypeAnywhere  begin
95c98db70     near: Integer ) ; var q : >>> TNoSuchTypeAnywhere ; begin
substituted   near: z : LongInt ; w : >>> TNoSuchTypeAtAll ; begin
```

The last row is a probe built for the zeroing arm: the template says `z: T` and
the specialization is `<LongInt>`, so printing `LongInt` shows that arm is live
rather than merely untested.

**Three sites buffered a template token, not one** -- found only because an edit
asserted a unique match and failed. They go through `CaptureTemplateTokenFrom`
now.

Gate: the ticket's grep, added to the `test_generic_errloc` recipe and run
THROUGH the recipe (`make -n`, then execute) rather than by hand. Positive
control: the same grep against the pinned compiler's output FAILS, so the row
can. `gate.sh quick` GREEN with `compiler/**` uncommitted (FPC seed canary PASS,
not SKIP). The quick tier does not exercise the specializer and the self-host
fixedpoint cannot -- `compiler.pas` has no generics -- so the 47 generic test
blocks from `make -n test-core` were run under their own recipes: 266 logical
commands, 0 failures.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b294f903a.

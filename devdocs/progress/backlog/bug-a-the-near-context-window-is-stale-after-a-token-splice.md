---
slug: bug-a-the-near-context-window-is-stale-after-a-token-splice
track: A
prio: 45
type: bug
status: backlog
blocked-by: []
summary: "`InsertTokens`/`RemoveTokens` shift `Tokens[]` and adjust the source-range and DWARF tables, but do NOT shift the parallel `TokSrcOff[]`/`TokSrcLen[]` arrays that `WriteTokenContext` prefers for a token's source spelling. After any splice, every `near:` window past the edit prints the spelling that used to live at that index. Visible today on a generic specialization: the window prints `< T > = class public >>> Val : T` — un-substituted `T`, which cannot occur in a substituted body — for an error whose token is `TNoSuchTypeAnywhere` in the spliced body. Filed by Track P; the fix is in lexer.inc, which is Track A ground."
owner: unassigned
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

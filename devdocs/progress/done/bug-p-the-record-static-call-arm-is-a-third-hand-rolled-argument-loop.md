---
slug: bug-p-the-record-static-call-arm-is-a-third-hand-rolled-argument-loop
title: "The record static / advanced-record ctor call arm is a THIRD hand-rolled argument loop with none of the doors"
track: P
prio: 35
type: bug
status: done
owner: frankH
created: 2026-09-09
found-by: frankS
tags: [methods, arity, records, array-of-const]
blocked-by: []
summary: "`pasparser_expr.inc`'s advanced-record ctor / static-method arm hand-rolls a THIRD argument loop, distinct from the two that bug-p-the-bare-self-call-in-expression-position-has-none-of-the-doors is extracting, and it has the same omissions. Measured 2026-09-09 at compiler fd01b434e7ff, `TR = record class function One(x: Integer): Integer; static; end`: `TR.One(1, 2, 3)` is ACCEPTED and answers 3 -- the arguments shifted -- and `TR.One()` is ACCEPTED and answers 12, uninitialised memory. fpc 3.2.2 refuses both. The loop is `while CurTok.Kind <> tkRParen do ParseExpr` with no bracket door (TryParseBracketArgForSlot), no bare-method-name door (TryDelphiBareProcArg), no arity pre-check and no ExpectCallRParen tail, so it cannot absorb an elided `array of const` either. FILED SEPARATELY AND ON PURPOSE: the bare-self extraction cannot reach it -- it is a different arm with a different receiver shape -- so closing that ticket must not read as closing the class. A second, narrower gap fell out of the same probe and is noted in the body: `class function Desc(const a: array of const): Integer; static` inside a RECORD is refused outright with `unknown type: const`, so the array-of-const doors cannot even be tested at this arm yet."
---

# The record static call arm is a third hand-rolled argument loop

```pascal
{$mode objfpc}{$modeswitch advancedrecords}
type TR = record class function One(x: Integer): Integer; static; end;
...
WriteLn(TR.One(7));         { 7   -- correct }
WriteLn(TR.One(1, 2, 3));   { 3   -- fpc: Wrong number of parameters }
WriteLn(TR.One());          { 12  -- fpc: Wrong number of parameters }
```

`pasparser_expr.inc`, the arm around the `rcCi` / `rcMmi` / `rcSelf` locals:

```pascal
if CurTok.Kind = tkLParen then
begin
  Next;
  while CurTok.Kind <> tkRParen do
  begin
    ParseExpr;
    ...
  end;
  Expect(tkRParen, ')');
end;
```

Unbounded, `ParseExpr` only, `Expect` rather than `ExpectCallRParen`.

## Why it is a separate ticket

[[bug-p-the-bare-self-call-in-expression-position-has-none-of-the-doors]] is
extracting the two IMPLICIT-SELF loops into one routine. This is a third loop
on a different arm — a qualified receiver that is a record TYPE NAME, reached
through the ctor/static path — and the extraction does not pass through it. If
it is not written down, the class closes on paper while the third copy keeps
its holes, which is precisely the failure the parent ticket documents happening
five times in a row.

Whoever takes it should almost certainly route this arm through the same shared
routine rather than porting the doors a fourth time, but the Self handling
differs (`UMthNoSelf` / a lifted record temp / a `-1` self, per `73e05b3e1`), so
it is not a one-line substitution and that is the work.

## The narrower gap the probe hit first

```pascal
type TR = record
  class function Desc(const a: array of const): Integer; static;
end;
```
`pascal26:5: error: unknown type: const` — `array of const` is not accepted as a
parameter of a record method at all. So the bracket and variadic-tail doors
cannot be exercised at this arm until that is fixed, and the arity rows above
are what is measurable today. Not split into its own ticket because it is one
sentence and the same file; measure it again before assuming it is still true.

## How it was found

frankH asked, in a claim-collision handover, whether the record-static arm one
page up in the same file shares the loop being extracted. It does not. The
question is the whole finding — the answer took one probe.

---

## Fixed 2026-09-09 (frankH) — the third arm joins the shared routine

`ParseBareSelfCallArgs` is now `ParseSharedCallArgs` and all **three** loops call
it. The rename is not cosmetic: the old name asserted a scope the routine no
longer has, and a name that is 80% accurate is worse than one that is 0%.

### What the third arm needed that the other two did not

Two things, and both are why the ticket said this is not a one-line
substitution:

1. **`selfBase`.** A `static` method has NO Self, so `Params[0]` is a REAL
   parameter and "how many arguments does this require" is off by one between
   the two flavours. `ApplyEmptyCallParens` hardcoded 1 and now takes it —
   `GenMakeStaticMethodCall` already carried the same quantity under the same
   name. With the method-flavoured 1, a one-parameter static reads as requiring
   none, so `Opt()` would silently take the default instead of refusing.
2. **An EMPTY argument chain.** With no Self there is no head `AN_ARG`, so the
   first argument goes into `ASTLeft[callNode]` — the empty-chain convention
   `GenMakeStaticMethodCall` already speaks, and the reason `lastArg` is allowed
   to arrive as `-1`. One `AppendArg` inside the routine rather than an `if` at
   each of the two append sites.

`selfBase` is derived from **whether a Self arg was actually hung**
(`rcSelf >= 0`), not from `UMthIsStatic`, so all three shapes that reach this
arm answer for themselves: no Self at all, a dummy `AN_INT_LIT` Self for a
static that still has the slot, and a lifted record temp for a constructor.
That distinction is `73e05b3e1`'s subject and asking `UMthIsStatic` would have
got the middle case wrong.

### Measured

| call | before | after | fpc 3.2.2 |
| --- | --- | --- | --- |
| `TR.One(1, 2, 3)` vs `One(a: Integer)` | **3** (arguments shifted) | refused | refused |
| `TR.One()` vs the same | **12** (uninitialised) | refused | refused |
| `TR.Create(1, 2, 3)` vs `Create(ax, ay)` | accepted | refused | refused |
| `TR.Create(1)` vs the same | accepted | refused | refused |
| `TR.One(7)` | 7 | 7 | 7 |
| `TR.Opt()` / `TR.Opt` / `TR.Opt(9)` | 5 / 5 / 9 | 5 / 5 / 9 | 5 / 5 / 9 |
| `TR.None` / `TR.None()` | 42 / 42 | 42 / 42 | 42 / 42 |
| `TR.Create(3, 4).Sum` and the chained `TR.Create(7, 8).Sum` | 7 / 15 | 7 / 15 | 7 / 15 |

Every accepted row is byte-identical to `fpc -Mobjfpc`.

### The accept fixture CANNOT fail for this defect, and it says so

`test_p_a_record_static_call_is_checked_like_every_other_call.pas` is
**byte-identical on the pinned pre-fix compiler** — the broken loop got the
GOOD calls right, because appending whatever it parsed builds the same tree
when the arity already matched. It is a must-not-break control for `selfBase`
and nothing more, and both its header and its Makefile row say that rather than
letting a green there read as coverage.

`test_p_a_record_static_call_arity_fail.pas` is the one with a positive
control: **the pin compiles it clean, exit 0, no diagnostics.** All four bad
rows live in one file because these come from `ErrorRecover`, not `Error`, so
one pass finds them all — and the ROW ASSERTS THE COUNT, because a change that
made one row halt would take the other three with it, which a bare `!` on the
compiler cannot see.

### The narrower gap the ticket noted is still true

`class function Desc(const a: array of const): Integer; static` inside a RECORD
is still refused with `unknown type: const` (re-measured, not assumed). So the
bracket and variadic-tail doors cannot be exercised at this arm yet; the arity
rows are the whole measurable surface, and the varrec carve-out is carried into
the pre-check for symmetry rather than because it can fire today.

### Three arms, one loop — the class is closed

That sentence is the one to distrust, so: the population was enumerated by
POSITION rather than by grep — every argument loop that appends `AN_ARG` nodes
against a `Procs[]` signature — and the three that hand-rolled are these three.
The seven loops behind `ExpectCallRParen` were already shared. If a fourth
turns up, it will turn up the same way this one did: by someone asking whether
a specific arm shares the loop, and measuring instead of reading.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2af86c169.

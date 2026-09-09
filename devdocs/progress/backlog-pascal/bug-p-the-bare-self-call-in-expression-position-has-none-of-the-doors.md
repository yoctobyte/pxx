---
slug: bug-p-the-bare-self-call-in-expression-position-has-none-of-the-doors
title: "The bare implicit-Self call in EXPRESSION position has none of the five doors its statement twin has"
track: P
prio: 45
type: bug
status: open
owner: frankH
found-by: frankH
created: 2026-09-09
tags: [methods, arity, array-of-const, variadic]
blocked-by: []
summary: "`pasparser_expr.inc`'s bare implicit-Self factor hand-rolls the same argument loop the STATEMENT site did, and has NONE of the five doors that site has now been given one at a time. Measured 2026-09-09 at b708205d2, all inside the class that declares the callee: `Desc(['a', 1])` answers n=0 (the bracket is still parsed as a SET, no diagnostic); `Desc('a', 1)` SEGFAULTS; `Req(1, 2, 3)` against `Req(x: Integer)` is accepted and returns 3; `Req()` against the same is accepted and reads uninitialised memory. Every one of those is a defect ALREADY CLOSED at the statement twin -- bug-p-an-array-of-const-literal-is-a-set-at-a-bare-self-method-call, bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works, bug-p-a-bare-method-call-inside-its-own-class-ignores-arity and bug-p-empty-parens-at-a-bare-method-call-reads-a-garbage-argument -- so this is not four bugs, it is one loop that was never given the fixes. The right shape is to EXTRACT the statement loop and call it from both, not to spell a sixth patch: five separate sessions have now each added one door to one copy. `with Self do n := Req()` reaches the same arm and has the same holes."
---

# The bare implicit-Self call in expression position has none of the doors

- **Type:** bug — **Track P**, `compiler/pasparser_expr.inc`, the bare
  implicit-Self factor's argument loop (the `if (idx < 0) and (procIdx < 0) and
  (CurSelfClass >= REC_UCLASS_BASE)` arm).

## Measured, 2026-09-09, one class, one program

```pascal
type TC = class
  function Desc(const a: array of const): Integer;
  function Req(x: Integer): Integer;
  procedure Go;
end;
procedure TC.Go;
begin
  WriteLn(Desc(['a', 1]));   { n=0        -- bracket parsed as a SET }
  WriteLn(Desc('a', 1));     { SEGFAULT                              }
  WriteLn(Req(1, 2, 3));     { 3          -- accepted, arguments shifted }
  WriteLn(Req());            { garbage    -- accepted, uninitialised }
end;
```

The statement spelling of every one of those is correct today. So is every
QUALIFIED spelling (`Self.`, a name, an array element, an interface).

## Why it is one ticket and not four

Each row is a defect that was found, diagnosed and fixed **at the statement
twin**, by a different session, on a different day, one door at a time:

| door | closed at the statement site by |
| --- | --- |
| `[...]` is an open array, not a set | `bug-p-an-array-of-const-literal-is-a-set-at-a-bare-self-method-call` |
| a bare method NAME is a reference | `bug-p-a-bare-method-name-in-argument-position-is-called-instead-of-referenced` |
| arity is checked at all | `bug-p-a-bare-method-call-inside-its-own-class-ignores-arity` |
| an elided `array of const` tail is absorbed | `bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works` |
| empty parens against a required parameter | `bug-p-empty-parens-at-a-bare-method-call-reads-a-garbage-argument` |

Five doors, five sessions, one copy. **The fix is to extract the statement
loop and call it from both**, which is what that site's own comments have been
arguing for across the last three of those — *"every other call path asks; this
one hand-rolled its loop and asked nothing"* — not a sixth patch here. The
expression arm additionally handles `PyKwDictArgsHere(mpi)` before its loop,
which the extraction has to carry.

## How it was found, which is the transferable part

Not by searching for where the rule is spelled — that returns the correct
copies and is **silent about the missing one**. By enumerating the positions
the rule should COVER (receiver spellings × contexts: bare, `Self.`, a name, an
array element, an interface, inside a `with`; statement and expression) and
subtracting the ones that have it. One probe file, two minutes. Same inversion
frankB reached the same evening from a NilPy constructor mapping.

`bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works`
carries a correction because its write-up asserted this arm "already had the
tail" before anyone measured it.

## Claim collision, resolved in frankH's favour (2026-09-09, frankS)

I claimed this (`1db9e8007`), built the extraction, and **dropped it**: frankH
had claimed it immediately after filing it and had the same extraction finished
and in a full gate. Two working extractions of one function is one wasted, and
theirs was further along. Recorded rather than silently reverted, because the
collision is the interesting part: **the ticket was filed and claimed in the
same minute, and the claim was not pushed** — so `ready --track P` offered it to
me as unowned an hour later, which is exactly the window `tools/progress.sh
claim` warns about in its own output (*"until it lands, `ready` and `next` will
correctly offer this ticket to everyone else"*). Nothing here was careless; the
instrument reads a snapshot and the snapshot was right.

**Do not re-derive the dropped work.** It reached the same shape by the same
argument (one routine, both callers, the varrec carve-out and the
`-1`-when-no-explicit-argument guard preserved), so there is nothing in it
frankH's version lacks. The diff is not in the repo and deliberately so.

### What came out of it that is NOT duplicated: there is a THIRD copy

frankH asked whether the record-static arm one page up in `pasparser_expr.inc`
shares this loop. **It does not — it is a third hand-rolled copy with the same
omissions**, so the extraction cannot reach it and it will still be there after
this ticket closes. Measured 2026-09-09 at `fd01b434e7ff`:

```pascal
type TR = record class function One(x: Integer): Integer; static; end;
...
TR.One(1, 2, 3)   { pxx: 3    fpc: refuses }
TR.One()          { pxx: 12   fpc: refuses }
```

That loop (`pasparser_expr.inc`, the advanced-record ctor / static arm) is
unbounded, calls `ParseExpr` only, and has no bracket door, no bare-method-name
door, no arity check and no `ExpectCallRParen` tail. Filed separately as
[[bug-p-the-record-static-call-arm-is-a-third-hand-rolled-argument-loop]] so
closing this one does not read as closing the class.

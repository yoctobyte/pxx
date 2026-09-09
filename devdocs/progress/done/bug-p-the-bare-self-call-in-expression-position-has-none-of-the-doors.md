---
slug: bug-p-the-bare-self-call-in-expression-position-has-none-of-the-doors
title: "The bare implicit-Self call in EXPRESSION position has none of the five doors its statement twin has"
track: P
prio: 45
type: bug
status: done
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

---

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

---

## Fixed 2026-09-09 (frankH) — by extraction, as the ticket argued

`ParseBareSelfCallArgs` (`compiler/pasparser_call.inc`) is now the one argument
loop for a bare implicit-Self call, and both copies were deleted and routed
through it: the statement arm in `pasparser_stmt.inc` and the factor arm in
`pasparser_expr.inc`. About 12.4k characters of duplicated loop went with them.

### Measured before and after, one class, one program

| call | before | after |
| --- | --- | --- |
| `Desc(['a', 1])` in an expression | `n=0` (bracket read as a SET) | `n=2` |
| `Desc('a', 1)` in an expression | SEGFAULT | `n=2` |
| `Desc('a')` in an expression | SEGFAULT | `n=1` |
| `Req(1, 2, 3)` vs `Req(x: Integer)` | accepted, returned 3 | refused, one diagnostic |
| `Req()` vs the same | accepted, read garbage | refused, one diagnostic |
| `Two(7)` vs `Two(a, b)` | accepted | refused, one diagnostic |
| `with Self do n := Req(1, 2, 3)` | accepted | refused, one diagnostic |

`Opt()`, `Opt`, `Opt(9)` on an all-defaulted signature are unaffected in both
positions — the strict arity check accounts for defaults.

### The three things extraction nearly breaks, all carried

1. **The varrec carve-out.** `UMethNameCanAbsorbVarRecTail` is ported to the
   expression arm with the pre-check, because variadic bracket-elision passes
   MORE explicit arguments than the signature has *on purpose* and fpc refuses
   that source — an arity gate written from fpc's answer alone deletes a pxx
   extension in silence. frankS's sentence, kept verbatim.
2. **`PyKwDictArgsHere(mpi)`**, which only the expression arm asked. It lives in
   the shared routine now; that is safe *because* it is guarded on `isNilPy`,
   so it is inert for Pascal — `f(a=1)` in Pascal stays a comparison.
3. **The `-1` when no explicit argument was parsed.** `lastArg` still being the
   entry value means empty parens, and handing that to `AbsorbVariadicTailArgs`
   wraps the implicit Self POINTER as element 0.

### One mistake, one diagnostic — and whose check owns it

Bounding the expression loop makes a surplus reach `ExpectCallRParen`'s tail,
which would report the same mistake a second time under the qualified wording.
The pre-check stays the single authority at BOTH sites, confirmed with frankS
who owns it: the shared tail is structurally blind to the too-few direction (a
short call leaves `CurTok` on `)`), so giving it the surplus direction would
split one site's arity reporting across two wordings depending on which way the
count was wrong.

### TWO OF THREE ARMS. The third is named, in the ticket AND in the code

The **record-static** call arm is a third hand-rolled copy with the same
omissions, and this routine cannot reach it — its Self handling genuinely
differs (`UMthNoSelf`, a lifted record temp, or a `-1` self). Measured by
frankS at `fd01b434e7ff`: `TR.One(1, 2, 3)` against a one-parameter `static`
gives 3, and `TR.One()` gives 12 — uninitialised memory, exit 0, no
diagnostic. Filed as
[[bug-p-the-record-static-call-arm-is-a-third-hand-rolled-argument-loop]],
and written into `ParseBareSelfCallArgs`'s own header.

Saying it out loud is the point: this ticket's whole argument is that the class
kept closing on paper while a copy kept its holes, five times running. A
resolution that says "extracted, done" closes it the same way.

Note for whoever takes it: `class function Desc(const a: array of const):
Integer; static` inside a RECORD is refused outright with `unknown type:
const`, so the array-of-const doors cannot be exercised at that arm at all
today — the arity rows are the whole measurable surface.

### Verification

- `test/test_p_a_bare_variadic_method_call.pas` grew an EXPRESSION half: every
  statement row now has an `x-` twin printing the same descriptor, through the
  second parser arm, plus two `with Self do` rows. Two functions rather than
  one, because a length alone cannot tell a correct descriptor from a
  differently-wrong one — `DescTag` reads the LAST element's tag, which is the
  slot the old loop filled with whatever the second argument left.
- Statement side unchanged on all six of its fixtures, including
  `test_p_a_bare_method_call_ignores_arity_fail` at exactly four diagnostics on
  lines 42-45 and `test_p_empty_parens_at_a_bare_method_call_fail` at line 43.
- Positive control: the pinned compiler segfaults on the fixture's first row.
- **Full tier run** (`PXX_ALLOW_FULL_SUITE=1 tools/gate.sh full`), because this
  change can REJECT source that previously compiled — an arity refusal at a
  site that had none — which is the one shape `--tier quick` cannot rule out.
  `make test-nilpy` PASSED (2011s), which is the run that matters most here:
  the shared routine absorbed the expression arm's `PyKwDictArgsHere` step.
  `make test` came back RED on **one pre-existing row**,
  `test_a_bracket_argument_reaches_the_same_door_at_every_call_path`
  (`FAIL constructor, open array of scalar: got 10 want 60`). **Not this
  change.** Controlled: stash, rebuild (`converged after 1 round(s)`,
  `f561030936e8`), run — it fails identically without any of this work.
  The pin answers `BRACKETDOOR OK`, and Track T had already filed it
  independently at `af0e5a0ad099` (`61f1fbb39`). Reported to frankS, whose
  `231ac5795` is the likely cause; not claimed here.
- **The first full run was discarded, not quoted.** Its verdict was invalid: I
  edited the fixture and its `.expected` while it was reading them. Killed,
  tree settled, restarted. The number above is the clean run.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b41f78b4e.

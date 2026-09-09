---
slug: bug-p-empty-parens-at-a-bare-method-call-reads-a-garbage-argument
title: "`Desc()` written bare inside its own class is accepted and reads a garbage argument"
track: P
prio: 35
type: bug
status: done
owner: frankH
found-by: frankH
created: 2026-09-09
tags: [methods, arity, array-of-const]
blocked-by: []
summary: "`Desc();` -- empty parens against a REQUIRED parameter -- is accepted at the bare implicit-Self statement site and the callee reads whatever was in the argument slot. Measured 2026-09-09 on `procedure Desc(const a: array of const)`: `Length(a)` answers 8 with no diagnostic, identical on HEAD and on pin v399, so this is pre-existing and not a regression. The qualified spelling `Self.Desc()` in the same program refuses it -- `Desc() requires 1 argument(s), none given` -- and fpc 3.2.2 refuses the bare one too (`Wrong number of parameters specified for call to \"Desc\"`). One concept, two paths, and the bare path is the one that stayed broken. The site's own hand-rolled argument loop has no FillDefaultArgs and no all-defaulted test, which is why a naive `no arguments parsed and ParamCount > 1 -> error` would break `Def()` on `Def(x: Integer = 3; y: Integer = 4)`, which works today and matches fpc (`def 34`). Found while fixing bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works, which touches this exact loop and deliberately left the shape alone rather than reshape it from a fix aimed at the segfault."
---

# Empty parens at a bare method call reads a garbage argument

- **Type:** bug — **Track P**, `compiler/pasparser_stmt.inc`, the bare
  implicit-Self statement call site's hand-rolled argument loop.

## The repro

```pascal
type TC = class
  procedure Desc(const a: array of const);
  procedure Go;
end;
procedure TC.Desc(const a: array of const);
begin WriteLn('n=', Length(a)); end;
procedure TC.Go;
begin
  Desc();        { accepted -> prints n=8 }
  Self.Desc();   { refused: Desc() requires 1 argument(s), none given }
end;
```

Both are the same call. fpc refuses the bare one as well, so there is no
"we accept more than fpc" reading here — the value is simply garbage.

## Why it is not a one-line arity check

`ParamCount > 1` with nothing parsed is **not** the condition. The same loop
serves `Def()` on `Def(x: Integer = 3; y: Integer = 4)`, which prints `def 34`
under both pxx and fpc. The loop never grew a `FillDefaultArgs` step, so a
check written from the arity alone would delete that. The condition wanted is
the one `CheckMethodCallArity` already spells for the **no-paren** shape
(`pasparser_call.inc`): refuse only when the first unsupplied parameter has no
declared default. This is that guard's empty-parens twin, and reusing it is
the fix rather than a fourth hand-written one — see
`devdocs/dev/normalise-dont-special-case.md`.

## What is already known about this loop

Three omissions have been found in it and all three read the same:
*every other call path asks; this one hand-rolled its loop and asked nothing.*
The bracket door, the arity fallback, and the variadic tail
([[bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works]],
which recorded this defect at its `-1` guard and left it deliberately
untouched). A fourth patch here is weaker than routing the site through the
shared tail, which is where the other seven loops already ask.

---

## Fixed 2026-09-09 (frankH)

### The mechanism

Two of the three method-call routes ask this question at the `(`:

```pascal
if CurTok.Kind = tkRParen then
begin
  if all-remaining-parameters-defaulted then FillDefaultArgs(…)
  else if ParamCount > 1 then Error(name + '() requires N argument(s), none given');
  mai := ParamCount;
end;
```

The bare implicit-Self **statement** site had no such arm at all, so `Desc();`
fell straight through an argument loop that had nothing to do, and the callee
read the argument slot as it found it: `Length(a)` = 8 against
`const a: array of const`, no diagnostic, exit 0.

**Two copies did not drift — the copy that was never made is what stayed
broken**, which is `devdocs/dev/normalise-dont-special-case.md` exactly. So the
fix is not a third copy: the arm is extracted into `ApplyEmptyCallParens`
(`pasparser_call.inc`, beside `CanFillDefaultsFrom`, which it uses) and all
three sites now call it. The two existing sites are byte-for-byte the same
behaviour; the third gains it.

### It is not an arity test, and that is why it had not been written

`ParamCount > 1` with nothing parsed is the wrong condition. The same loop
serves `Def()` on `Def(x: Integer = 3; y: Integer = 4)`, which prints `def 34`
under pxx and under fpc 3.2.2 alike. The question is whether the first
**unsupplied** parameter carries a declared default — Pascal defaults are
trailing, so parameter 1 settles the whole tail.

### The test's assertion is a LINE NUMBER, deliberately

`Error` HALTS, so exactly one diagnostic ever prints from the fixture — and the
**pinned compiler refuses the file too**, at the QUALIFIED call on line 44. A
row asserting "refused", or asserting the message text, is green on the pin and
green on HEAD and measures nothing. Only *43 rather than 44* separates them,
because the bare call is now caught first. Verified in both directions: HEAD
reports 43, pin v399 reports 44.

### Verification

- `test/test_p_empty_parens_at_a_bare_method_call_fail.pas`, wired into
  `test-core`: `rc=1`, the refusal on line 43, no binary.
- Both spellings assert on adjacent lines, because the defect was that they
  disagreed — a fixture testing only the bare one goes green the day someone
  breaks the qualified one instead.
- The all-defaulted twin (`Def`, `Def(7)`, `Def(7, 8)`, `NoArg`, `NoArg()`)
  lives in `test_p_a_bare_variadic_method_call.pas` and is unchanged.
- **NilPy probe carried** (the two extracted sites are the NilPy method-call
  route, and `--tier quick` is Pascal-weighted): `c.d()` / `c.d(7)` /
  `c.d(7, 8)` on `def d(self, a=3, b=4)` print 34 / 74 / 78, `c.n()` on a
  parameterless method works, and `c.m()` on `def m(self, a)` still refuses —
  unchanged in both directions.
- Self-host `converged after 1 round(s)`; `tools/gate.sh quick` GREEN from a
  dirty tree, so the FPC seed canary ran.

### One diagnostic, not two — the same rule as the sibling fix

`Req()` against `Req(x: Integer)` is a too-few call, and the statement site's
arity pre-check catches BOTH directions, so running the new arm there as well
printed two diagnostics for one mistake. The arm is therefore skipped when the
pre-check has already spoken — the same rule
[[bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works]]
settled for the surplus direction, applied consistently rather than a second
rule for the second direction. The shapes the pre-check stays silent about (an
`array of const` carve-out, or no strict candidate at all) are exactly the ones
where this arm is the only thing asking, which is what `Desc()` is.

`Opt()`, `Opt`, `Opt(9)` on `Opt(x: Integer = 5)` are unaffected — the strict
arity check accounts for defaults, so it never fires on an all-defaulted
empty-parens call and the arm keeps ownership of it.

### And the search that found it found a bigger one

Enumerating the POSITIONS rather than grepping for the rule (receiver spellings
× contexts, one probe file) turned up two rows nothing refused:
`n := Req();` and `with Self do n := Req();` — the bare implicit-Self call in
EXPRESSION position, which is the statement loop's twin with **none** of the
five doors. It also segfaults on `Desc('a', 1)` and answers `n=0` to
`Desc(['a', 1])`. Filed at prio 45 as
[[bug-p-the-bare-self-call-in-expression-position-has-none-of-the-doors]] with
the four measured rows and the door/session table, and deliberately NOT folded
into this commit: the right shape there is to extract the statement loop and
call it from both, which is a different change from adding one more arm.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 86966fdea.

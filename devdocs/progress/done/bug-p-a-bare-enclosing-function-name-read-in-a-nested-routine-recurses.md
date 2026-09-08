---
slug: bug-p-a-bare-enclosing-function-name-read-in-a-nested-routine-recurses
title: "Reading the enclosing function's BARE name inside a nested routine is a recursive call here and the result VARIABLE in fpc"
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-09-07
summary: "Inside a NESTED routine, `Inner := F` -- the enclosing function's name, bare, parameterless, in a READ position -- compiles to a recursive CALL to F. fpc 3.2.2 reads the enclosing function's RESULT VARIABLE and does not call anything. Measured with a call counter so the two readings cannot be confused: fpc `calls=1`, pxx `calls=2`, pin v407 `calls=2` (so it predates the 2026-09-07 nested-result work and is untouched by it). The WRITE spellings are all correct now -- `F := x`, `F.FV := x`, `F[i] := x`, `F^ := x` from a nested procedure or function -- so this is the last position where the enclosing name does not mean the result. NOT a trivial widening of the same rewrite: rewriting a bare READ unconditionally would silently stop a genuine parameterless recursive call from a nested routine, so the fix has to decide what `F` with no parentheses means, and that is a dialect decision more than a parser one."
---

# Repro — the counter is the point

```pascal
program bare; {$mode objfpc}{$H+}
var calls, depth: LongInt;
function F: LongInt;
  function Inner: LongInt;
  begin
    if depth = 0 then begin Inc(depth); Inner := F; end else Inner := -1;
  end;
begin
  Inc(calls);
  Result := 40 + depth;
  WriteLn('  inner=', Inner, ' res=', Result, ' calls=', calls);
end;
begin calls := 0; depth := 0; WriteLn('final=', F, ' calls=', calls); end.
```

```
fpc 3.2.2      final=  inner=40 res=40 calls=1
               40 calls=1
pxx HEAD       inner=-1 res=41 calls=2 ... 40 calls=2
pin v407       identical to HEAD
```

**A value comparison alone could not have settled this** — the two readings can
produce the same number for the right depth. `calls` is the row that separates
them, and it is why the probe carries a counter rather than only a result.

# Why this is not one more token kind in the existing rewrite

`ParseNestedRoutine`'s enclosing-name rewrite now fires on `:=`, `.`, `[` and
`^`. Every one of those is unambiguously a result POSITION. A bare name in a
read position is the one spelling where a recursive call is a real competing
reading, and `test_a_nested_routine_assigns_the_enclosing_functions_result.pas`
carries `Recurse := Recurse(k - 1) + 1` as the control — though note that row is
**parenthesised**, so it does not actually exercise this question. There is no
in-tree assertion either way for a bare parameterless read.

So the choice is a dialect decision:

- **Match fpc**: inside a nested routine the enclosing name is always the result
  variable, and a recursive call must be spelled `F()`. This is old-Turbo-Pascal
  behaviour and is what fpc measurably does.
- **Keep today's**: a bare read is a call, which is what the name means in the
  enclosing function's OWN body.

Whichever is chosen, the two positions (own body vs nested routine) currently
agree with each other and disagree with fpc in the nested one. Say which
behaviour is intended in the ticket before touching the rewrite, and add the
counter probe as a row — a fixture asserting only the returned value will pass
under both readings for most depths.

# Not urgent

No in-tree code and no corpus row is known to spell it. Found while fixing
`bug-p-the-enclosing-functions-name-inside-a-nested-function-writes-the-nested-results`,
as the one remaining position after every WRITE spelling was closed.

# RESOLVED — and the ticket's central claim was wrong: this was not a dialect decision

The ticket says the fix "has to decide what `F` with no parentheses means, and
that is a dialect decision more than a parser one", and asks that the intent be
settled before the rewrite is touched. **It was already settled, and already
implemented, in the sibling path.** The own-body read in `ParseFactorCore` has
keyed on `not DelphiMode` since the paramless flip and reproduces both of fpc's
answers exactly, warning under `--warn-self-result`. `ParseNestedRoutine`'s
enclosing-name rewrite never consulted the mode at all, so it took the Delphi
reading in objfpc too. One concept, two paths, second path broken —
`normalise-dont-special-case`, not Track U.

**Why the ticket read it as a fork: it measured one mode.** Everything it
reports is true of `{$mode objfpc}` and it never ran `{$mode delphi}`, where our
behaviour was already correct. Measured 2026-09-08 against fpc 3.2.2, both
modes, with the ticket's own call counter:

| in a nested routine | fpc objfpc | fpc delphi | pxx before | pxx after |
| --- | --- | --- | --- | --- |
| `Inner := F` bare read | result var | **CALL** | CALL | matches both |
| `Outer.FV := 33` qualified | result var | result var | result var | unchanged |
| `F;` bare, statement | **Illegal expression** | **Illegal expression** | accepted | see below |

**The "widening would rewrite a recursion into a result read" worry, which is
written into the code twice, is true in Delphi mode only.** In objfpc there is
no competing call reading to protect: fpc rejects a bare `F;` outright in *both*
modes, so no legal program spells a recursive call that way from a nested
routine. Nothing had to be given up.

## The fix

`bareRead := (not DelphiMode) and (i + 1 < TokCount) and (Tokens[i + 1].Kind <>
tkLParen)`, OR-ed into the existing `:=`/`.`/`[`/`^` test. No special cases —
see below for the two I wrote before measuring and then deleted.

`F;` in objfpc now becomes `Result;` and is refused (`expected ':=' before ';'`)
where it used to compile as a recursive call. That is a deliberate consequence
and it moves us toward fpc, which refuses it too; the diagnostics differ in
wording, which is deferred.

## Two exceptions I invented on reasoning, and fpc refused both

Recorded because both looked like prudence and neither survived a measurement:

- **`@F` "obviously" wants the routine's address.** It does not. Inside a nested
  routine `p := @G; PLongInt(p)^ := 99` makes G return **99** under fpc — `@` of
  a bare enclosing name is the address of the *result variable*, because the
  name IS the result variable in every position but a call's `(`. The exception
  would have been a divergence wearing the shape of caution.
- **A preceding `.` needs excluding** (`r.F := 7` with a field named like the
  enclosing function). Already impossible: the tkIdent arm at the top of that
  scan skips any identifier following a dot before `nm` is read. Measured anyway
  — both compilers print `r.F=7, calls=1`. It would have been a condition that
  can never be false.

## Fixtures — two files, and each is proven to fail

`test/test_nested_bare_enclosing_name_objfpc.pas` and `..._delphi.pas`, wired
into `test-core`, `.expected` generated from fpc rather than written.

The counter is the assertion, as the ticket correctly insisted: both readings
return 40, so a value-only row passes either way.

**Each row was shown to bite, which is the part that is easy to skip because
both files are green:**

- objfpc — **fails** with the fix reverted (`calls=2` against fpc's 1).
- delphi — passes with the fix reverted, because that cell was never broken. So
  it was verified against the *over-broad repair* instead: dropping the
  `not DelphiMode` test turns it **red** while objfpc stays green. That repair
  is exactly the one this ticket's own framing invited, and before today no
  in-tree row would have caught it — the control the ticket names is
  parenthesised and never exercises the bare spelling.

Self-host fixedpoint holds (`converged`, `006274f6d15d`).

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 85912e1fa.

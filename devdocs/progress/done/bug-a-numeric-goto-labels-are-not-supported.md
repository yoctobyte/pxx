---
slug: bug-a-numeric-goto-labels-are-not-supported
track: A
prio: 25
status: done
---

# Numeric goto labels are not supported

Standard Pascal spells a label as a *digit sequence*; FPC accepts both that and
an identifier. pxx accepts only the identifier form.

```pascal
program lab_num;
label 10;
var k: Integer;
begin k := 1; goto 10; WriteLn('no'); 10: WriteLn('yes'); end.
```

```
pascal26:2: error: unexpected token
  near: program lab_num  label >>>   var
```

fpc 3.2.2 (`-Mobjfpc -O1`) compiles it and prints `yes`.

## Scope

Three sites, all in the Pascal frontend:

1. `ParseLabelSection` (`compiler/pasparser_decl.inc`) — accept `tkInteger`
   beside `tkIdent`. One token-kind test; the recorded key is already a raw
   source slice (`SOffset`/`SLen`), so `10` stores and compares fine as-is.
2. `goto` (`compiler/pasparser_stmt.inc`, the `CaseEqual(name, 'goto')` arm) —
   `if CurTok.Kind <> tkIdent then Error('expected label name after goto')`.
3. The statement-position placement `10:`, which today only recognises
   `ident ':'`.

Matching is `TokSlicesMatch` over raw slices throughout, so nothing downstream
cares that the slice is digits. Site 3 is the one with a parsing hazard: a
statement starting with an integer literal is otherwise meaningless, so the
lookahead for a following `:` is unambiguous, but it must not fire inside a
`case` arm, where `10:` is a case label.

## Why this is low priority

Numeric labels are a 1970s spelling; the identifier form works, and no code in
this repo, in `lib/**`, or in the FPC-sourced corpora uses them. Filed for
completeness after the ordering bug
(`bug-a-a-label-section-must-come-last-in-a-routine`) was fixed in the same
code — that fix deliberately did **not** widen the section parser to
`tkInteger`, because accepting the declaration while sites 2 and 3 still reject
the use would turn a clean syntax error into a confusing one.

## Found by

The same control-flow differential sweep as the ordering bug.

---

# Already FIXED — closing with a regression test, 2026-08-27

Re-measured before acting, per the "verify at current HEAD" rule. **All three
sites work**, and have since `015bbbaf2` (2026-08-22), *"fix(P): a routine's
label section clobbered the program's labels; numeric labels"* — the very
follow-up this ticket said had deliberately **not** been done:

> that fix deliberately did **not** widen the section parser to `tkInteger`,
> because accepting the declaration while sites 2 and 3 still reject the use
> would turn a clean syntax error into a confusing one.

It did widen it, and it did sites 2 and 3 with it. `ParseLabelSection` now reads
`while (CurTok.Kind = tkIdent) or (CurTok.Kind = tkInteger)`, with
`LabelSpanOfTok` giving a numeric token the same span an identifier has. The
ticket was simply never closed.

Confirmed on the **pinned** compiler too, so this predates the 2026-07-27 pin's
successor and is not a today's-work artefact.

## Closed with a test rather than just a status change

The reason to spend a commit here: this was a *stale* ticket, which means the
behaviour was unguarded — nothing in `test-core` covered numeric labels, so the
next person to touch the label parser could have taken them away silently and
re-created this ticket for real.

`test/test_numeric_goto_labels.pas` (wired into `test-core`) is
**byte-identical to the FPC 3.2.2 oracle** across six rows:

- a program-level `label 10, 20;` with a forward `goto` over dead code;
- **the hazard this ticket named** — a numeric `case` arm (`10:`) in the same
  routine as a numeric goto label `10:`, which must not be confused;
- numeric labels inside a **routine**, with a **backward** jump used as a loop
  (`CountTo(4)` = 10);
- **mixed** identifier and numeric labels in one routine's `label` section;
- a label as the last thing before `end`.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.

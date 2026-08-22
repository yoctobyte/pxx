---
slug: bug-a-numeric-goto-labels-are-not-supported
track: A
prio: 15
status: backlog
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

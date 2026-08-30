---
slug: bug-p-result-is-not-a-method-pointer-lvalue
track: P
prio: 40
type: bug
status: backlog
owner: unassigned
blocked-by: []
summary: "`Result := s.Pick` inside a function returning a method pointer is refused with `\"TSvc.Pick\" is a procedure and has no result to use in an expression`, for EVERY receiver spelling, while `t := s.Pick; Result := t` on a local of the same type compiles and runs. FPC accepts the direct form. Cause: the implicit `Result` symbol is allocated by `AllocVar('Result', retType)` (pasparser_proc.inc:2310) as a plain var, so it carries no `SymProcSig` and its `TypeKind`/`RecName` never look like a method-pointer lvalue — and the assignment arm that recognises the method-pointer context keys on exactly `SymProcSig[idx] >= 0` and `Syms[idx].TypeKind = tyRecord`. A THIRD axis, orthogonal to receiver spellings: the LHS spelling."
---

# `Result` is not recognised as a method-pointer lvalue

## Measured — binary `490a2cfd83a2`, and identically on `pinned`

```pascal
program tres;
{$mode delphi}
type
  TSel = procedure of object;
  TSvc = class procedure Pick; end;
procedure TSvc.Pick; begin writeln('picked'); end;
function FreeFn(s: TSvc): TSel;
begin
  Result := s.Pick;      { <-- refused }
end;
```

```
pascal26:11: error: "TSvc.Pick" is a procedure and has no result to use in an expression
```

FPC 3.2.2 compiles and prints `picked`. The workaround compiles here and is what
every existing test in the tree happens to use:

```pascal
  t := s.Pick;   { a LOCAL of type TSel -- fine }
  Result := t;
```

**Not a receiver problem.** All three receiver spellings fail identically with
`Result` on the left (`s.Pick`, `Self.Pick`, bare `Pick`), and all three succeed
with a local on the left. The variable is the LHS.

## Why

The assignment site recognises "a method pointer is wanted here" by asking two
questions about the LHS symbol:

```pascal
  if DelphiMode and (idx >= 0) and (SymProcSig[idx] >= 0) and
     (Syms[idx].TypeKind = tyRecord) then
    mrefNode := TryParseParenlessMethodRef;
```

`SymProcSig` is set when a variable is DECLARED with a procedural type. The
implicit result variable is not declared; it is allocated by
`AllocVar('Result', retType)` (`pasparser_proc.inc:2310`) from the return type
alone, and nothing copies the alias's procedural signature onto it. So
`SymProcSig[Result]` is -1 and the arm never fires.

The same is presumably true of every other consumer of `SymProcSig` on an
lvalue, which is worth grepping before fixing — this ticket names one symptom
of what may be a general gap in how the result symbol is furnished.

## The likely fix, and the reason it is filed rather than done

Carry the procedural signature (and whatever else the alias row holds —
`AliasProcSig`, `MethodPtrRecId` for `RecName`) onto the result symbol at
allocation time, so `Result` is furnished the way a declared variable of the
same type is. That edit is in the RESULT-SYMBOL setup, which every function in
every mode goes through, so it wants its own gate run rather than riding along
with a parser fix. Found while fixing arm A of
[[bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings]];
recorded there and here rather than folded in.

## Gate

The repro above, plus the two receiver-spelling variants, each **calling
through** the returned pointer rather than only asserting it is non-nil. Oracle:
FPC (`tools/fpc_diff_probe.sh`).
`test/test_method_pointer_bare_receiver_and_call_reading.pas` documents the gap
in its header and uses locals throughout because of it — when this is fixed,
that test is the natural place to add the direct `Result :=` rows.

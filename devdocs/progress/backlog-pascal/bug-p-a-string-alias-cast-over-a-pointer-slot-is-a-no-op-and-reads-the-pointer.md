---
slug: bug-p-a-string-alias-cast-over-a-pointer-slot-is-a-no-op-and-reads-the-pointer
title: "A string-alias cast over a Pointer slot is treated as a no-op, so the expression stays a pointer"
track: P
prio: 55
type: bug
status: backlog
found: 2026-09-05
found-by: frankH
owner: ""
blocked-by: []
summary: "`type t = AnsiString; var p: Pointer; t(p) := 'abc'; writeln(t(p))` prints `4261104` -- the POINTER rendered as a number -- where fpc 3.2.2 -Mdelphi prints `abc`. Silent wrong value, no diagnostic. The loud face of the same cause is `SetLength(t(p), 2)` answering `SetLength expects a string variable in IR codegen` while fpc accepts it and prints `ab`. CAUSE, located: the C4 string-alias cast arm in pasparser_expr.inc treats the cast as a VALUE-LEVEL NO-OP and returns the operand with its own kind. That is correct and load-bearing when the operand is already a string (tagging it tyPointer is what made `Pos(tbtstring(' '), s)` miss every string overload) and wrong when the operand is a POINTER, where the same cast is a real REINTERPRET. THE OPERAND'S KIND IS THE DISCRIMINATOR, not the alias's. Boundary measured: casts over a string VARIABLE, a `^AnsiString` deref, and an AnsiString record FIELD all work; only a Pointer-typed slot fails, with or without indirection. A RETYPE-ONLY FIX WAS TRIED AND REVERTED, and the reason is the useful part: retagging the node to tyAnsiString makes `writeln(t(p))` print `abc` followed by out-of-bounds memory and leaves `Length(t(p))` answering the pointer value (4265208 against fpc's 3), because the IR still lowers the load as a pointer -- the store is already CORRECT (`p = Pointer(s)` is TRUE). So the fix spans the parser AND ir.inc's lvalue/length lowering, not the cast arm alone. Third face of the cause 9339d6661 fixed the second of."
---

# A string-alias cast over a Pointer slot is treated as a no-op, so the expression stays a pointer

- **Type:** bug — silent wrong value, plus a spurious refusal from one cause
- **Track:** P (Pascal frontend), with an `ir.inc` half — see below
- **Found while:** re-measuring [[feature-embed-pascal-script]], whose remaining
  wall this is. That ticket recorded only the loud half.

## The two faces, both measured 2026-09-05 against `fpc 3.2.2 -Mdelphi`

```pascal
type t = AnsiString;
var p: Pointer;
begin
  t(p) := 'abc';
  writeln(t(p));        { pxx: 4261104     fpc: abc }
  SetLength(t(p), 2);   { pxx: SetLength expects a string variable in IR codegen
                          fpc: compiles, prints ab }
end.
```

The silent one is the dangerous one and is **not** what the pascal-script ticket
describes: it says the wall is `SetLength`. A pointer printed as a number is a
plausible-looking value, and this idiom appears **93 times in `uPSCompiler.pas`
alone** — it is how that codebase stores every string.

## The boundary, varied rather than assumed

| operand of the cast | `SetLength(t(...), 2)` |
| --- | --- |
| `var s: AnsiString` | works |
| `p^` where `p: ^AnsiString` | works |
| record field of type `AnsiString` | works |
| `var p: Pointer` | **fails** |
| `Pointer` field, reached directly | **fails** |
| `Pointer` field through a record pointer | **fails** |

So it is not the indirection and not the record — it is that the underlying slot
is `Pointer`-typed, which is exactly when the cast stops being a no-op and
becomes a reinterpret.

## Cause

`pasparser_expr.inc`, the C4 alias-cast arm (`strAliasCast`). It exits with
`LastExprTk := IntToTypeKind(ASTTk[CurASTNode])` — the OPERAND's own kind. Its
comment says *"a value-level no-op, NOT a pointer reinterpret. Keep the operand
node and its own string kind"*, which assumes the operand is a string. The
`tyRecord` arm directly below is the model for the other case: it **retypes** the
node rather than returning it unchanged.

This is the **third face** of the cause `9339d6661` fixed the second of (*"a cast
to a string alias no longer drops the index that follows it"*). Same arm, same
assumption, one operand type over.

## A retype-only fix was tried and REVERTED — this is the part worth reading

Making the arm retype the node when the operand is not already a string (keeping
the no-op when it is, since that is load-bearing for `Pos(tbtstring(' '), s)`)
is the obvious change and it is **not sufficient**:

- `writeln(t(p))` then prints `abc` **followed by a run of out-of-bounds
  memory** — worse than the wrong number it replaced.
- `Length(t(p))` still answers `4265208`, the pointer value, against fpc's `3`.
- `SetLength(t(p), 2)` still refuses; that check is in IR codegen and does not
  read the node's retagged kind.

And the store is **already correct**: `t(p) := s; p = Pointer(s)` is `TRUE`, and
`Length(s)` is `3`. So the value in the slot is right and every READ path is
wrong. The fix therefore spans the IR lowering as well as the parser.

**CORRECTED 2026-09-05, same day, asked for by frank-optimize before it took
this ticket.** This paragraph first said the lowering "re-derives the type from
the SYMBOL rather than from the node", and called it the same durable-column
seam as the pointee-element bug. **That was a hypothesis written from the retag
not helping, and the code does not support it as stated.** The refusal is
`ir_codegen.inc:10778`, the final `else` of the `specialId = 101` chain whose
arms are `if IRKind[val1Node] = IR_LEA` then
`else if IRNodeIsFrozenStrAddr(val1Node)` — it dispatches on NODE predicates,
not on a symbol. The measured fact underneath is only this: retagging the AST
node's `ASTTk` did not change the refusal, so whatever those predicates read, it
is not that tag.

**Five siblings, so a fix keyed on the x86-64 arm alone will pass a native
gate and leave four targets refusing:** `ir_codegen386.inc:3284`,
`ir_codegen_aarch64.inc:3246`, `ir_codegen_arm32.inc:2613`,
`ir_codegen_riscv32.inc:2906`, `ir_codegen_xtensa.inc:3013`, each with the same
message under a target prefix.

The comment directly above that chain cites
`bug-a-setlength-is-refused-for-any-frozen-string-that-is-not-a-plain-symbol`,
and the `IRNodeIsFrozenStrAddr` arm is its fix. The case here is the next shape
past it — a `Pointer`-typed slot rather than a frozen-string address — so that
arm is the model and plausibly the place.

Reverted rather than shipped: a half-fix that turns a wrong number into an
out-of-bounds read is not an improvement, and CLAUDE.md's rule is to bank the
diagnosis and park it rather than microfix.

**The diff itself was restored with `git checkout --` and not stashed, which was
a mistake** — CLAUDE.md says park held work as a patch or a stash, and "reverted
because it was worse" is still held work if the next taker wants it as a
positive control. Reconstructed here so it is not lost: the arm's exit, today
`LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);`, became

```pascal
strAliasOpTk := IntToTypeKind(ASTTk[CurASTNode]);
if TypeIsFrozenString(strAliasOpTk) or
   (strAliasOpTk = tyAnsiString) or (strAliasOpTk = tyString) then
  LastExprTk := strAliasOpTk
else
begin
  ASTTk[CurASTNode] := AliasTk[aliasIdx];
  LastExprTk := IntToTypeKind(AliasTk[aliasIdx]);
end;
```

mirroring the `tyRecord` arm directly below, which already retypes rather than
returning the operand unchanged.

## What a fix has to satisfy

1. `writeln(t(p))` prints `abc`; `Length(t(p))` answers 3.
2. `SetLength(t(p), 2)` compiles and yields `ab`.
3. `Pos(tbtstring(' '), s)` still binds a string overload — the no-op path for a
   string operand must survive, it is why that arm exists.
4. A frozen-string alias operand keeps whatever it does today; only the
   non-string operand changes.

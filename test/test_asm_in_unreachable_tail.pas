{ AN ASM BLOCK IN THE UNREACHABLE TAIL MUST NOT DISABLE THE PRUNE.

  ASTSubtreeHasLabel walks the remainder behind a terminator looking for an
  entry point, recursing through ASTLeft/ASTRight. AN_ASM does not HAVE child
  nodes: its ASTLeft and ASTRight are an AsmBytes OFFSET and a LENGTH (see
  ParseAsmStatementAST), which ir.inc reads straight back out. Recursing into
  them indexes ASTKind with a byte offset, and the wrong answer is a spurious
  True -- "there is a label here" -- which SUPPRESSES a correct prune.

  That is what makes it observable at all, and it is why this test asserts a
  RUN rather than a size: never_asmprobe is declared and never defined, so a
  suppressed prune emits a call to it and the binary does not start. Before
  the fix that is exactly what happened, in this shape, at -O0 --
  `undefined symbol: never_asmprobe`. Diagnosed by frankb-a9 (Track C) from
  the field overloading; the visible consequence was found by running it.

  The sibling c_asm_in_unreachable_tail.c is not a formality: the C frontend
  builds AN_ASM in CAsmBuildBlock and reaches this guard through the AN_BLOCK
  walk, so it is a second route to the same node. Both were broken.

  Deliberately NOT asserting that the asm block itself is gone -- an asm block
  behind a terminator is unreachable and pruning it is correct, but this test
  is about the GUARD not wandering, so it asserts the consequence that a
  wrong answer has. }
program test_asm_in_unreachable_tail;
function NeverA: Integer; external name 'never_asmprobe';
procedure AfterExitWithAsm;
begin
  Exit;
  asm
    nop
  end;
  WriteLn(NeverA);
end;
begin
  AfterExitWithAsm;
  WriteLn('ASM TAIL OK');
end.

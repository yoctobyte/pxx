{$mode objfpc}
program test_shr_const_fold_typing;

{ A constant expression CONTAINING `shr` must fold, and the folded value must
  type the way FPC types a constant: the smallest signed type that holds it.

  Pascal's `shr` is lexed as an IDENTIFIER — the lexer mints no tkShr for it —
  so an AN_BINOP carrying it carries Ord(tkIdent). ASTConstIntValue's operator
  `case` had arms for tkShl and tkShr but none for tkIdent, so it fell through
  to `else Result := False` for every Pascal `shr`: the operand did not fold,
  the negation was typed Int64 rather than LongInt, and IntToHex picked its
  Int64 overload. The `shl` spelling of the same expression was right the whole
  time — the double case devdocs/dev/normalise-dont-special-case.md exists for.

  Rows B/C/E/F are the controls that made the failure legible: same shape,
  different operator, correct before and after.
  bug-a-shr-reaches-the-ir-spelled-as-tkident }

uses sysutils;
begin
  writeln(IntToHex(-(256 shr 4), 8));   { FFFFFFF0 — was FFFFFFFFFFFFFFF0 }
  writeln(IntToHex(-(256 shl 1), 8));   { FFFFFE00 — control: shl has a token }
  writeln(IntToHex(-(16), 8));          { FFFFFFF0 — control: no shift at all }
  writeln(not (256 shr 4));             { -17 }
  writeln(not (256 shl 1));             { -513 }
  writeln(not 16);                      { -17 }
end.

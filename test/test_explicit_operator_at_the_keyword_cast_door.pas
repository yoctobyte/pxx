program test_explicit_operator_at_the_keyword_cast_door;
{$mode objfpc}{$H+}
{ `Char`, `Boolean`, `Single`, `Double`, `Real` and `Extended` are lexer TOKENS;
  every other type name is an identifier. Both spellings of a cast reached
  ParseFactorCore and built their node in DIFFERENT places, and the keyword arms
  were the shared builder MINUS its first arm, TryExplicitOpCast. So with
  `operator Explicit(a: TRec): Boolean` in scope:

    Boolean(r)   reinterpreted the record's bytes  -> TRUE
    TMyBool(r)   called the operator               -> FALSE   (fpc: FALSE)

  A silent wrong value at one spelling of a cast whose other spelling was right.
  The float half failed louder and is the more findable one: `Double(r)` was
  REFUSED outright -- `incompatible types: cannot assign record to Double` --
  while `TMyDbl(r)`, an alias of the very same type, compiled.

  ROW 1 IS WHY THE OPERATOR ADDS ONE. The first probe wrote `res := Chr(a.v)`
  with a.v = 65, so the operator and the reinterpret BOTH answered 'A' and the
  row passed while the defect was live. An expected value that collides with the
  failure value is a row that cannot fail, whatever else is right about it.
  Chr(a.v + 1) separates them: 'B' is only reachable through the operator.

  Rows 2, 4, 6 and 8 are the alias spellings and were correct before the fix.
  They are the control: they are what made this a DRIFT between two doors rather
  than a missing feature, and if a later change breaks them the two doors have
  merely drifted the other way.

  Byte-identical to fpc 3.2.2 on all eight rows, and on i386 / aarch64 / arm32 /
  riscv32 under qemu.
  refactor-p-five-dispatch-sites-for-one-named-type-cast }
type
  TRec = record v: LongInt; end;
  TMyChar = Char;
  TMyBool = Boolean;
  TMyDbl  = Double;
  TMySgl  = Single;
operator Explicit(const a: TRec) res: Char;    begin res := Chr(a.v + 1); end;
operator Explicit(const a: TRec) res: Boolean; begin res := a.v > 100; end;
operator Explicit(const a: TRec) res: Double;  begin res := a.v / 4; end;
operator Explicit(const a: TRec) res: Single;  begin res := a.v / 8; end;
var r: TRec;
begin
  r.v := 65;
  WriteLn('1 Char keyword    ', Char(r));
  WriteLn('2 Char alias      ', TMyChar(r));
  WriteLn('3 Boolean keyword ', Boolean(r));
  WriteLn('4 Boolean alias   ', TMyBool(r));
  WriteLn('5 Double keyword  ', Double(r):0:4);
  WriteLn('6 Double alias    ', TMyDbl(r):0:4);
  WriteLn('7 Single keyword  ', Single(r):0:4);
  WriteLn('8 Single alias    ', TMySgl(r):0:4);
end.

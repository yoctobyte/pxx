{ The other spellings of the record-name shadow: a CLASS, an ENUM and a type
  ALIAS that share a name with one of the compiler's own records. IsRecordType
  answered the builtin record for all of them, so SizeOf(TProc) of a class was
  1344 and SizeOf(TSymbol) of a three-member enum was 104 (the pin also
  segfaults freeing the class). The ALIAS row was already right and is the
  control: an alias resolves before IsRecordType is asked. Each row compares
  against a control type of the SAME kind and an unshadowed name, so it carries
  no expected width and reads TRUE on every target.
  bug-a-fourteen-compiler-internal-record-names-shadow-any-user-type }
{$mode objfpc}
program test_a_class_or_enum_named_like_a_compiler_record_is_not_that_record;
type
  TProc = class X: Int64; function Get: Int64; end;
  TProcControl = class X: Int64; function Get: Int64; end;
  TSymbol = (sA, sB, sC);
  TSymbolControl = (cA, cB, cC);
  TParam = Word;
  TParamControl = Word;
function TProc.Get: Int64; begin Result := X * 2; end;
function TProcControl.Get: Int64; begin Result := X * 2; end;
var o: TProc; s: TSymbol; p: TParam;
begin
  o := TProc.Create; o.X := 21; s := sC; p := 65535;
  WriteLn(o.Get, ' ', Ord(s), ' ', p);
  WriteLn(SizeOf(TProc) = SizeOf(TProcControl), ' ',
          SizeOf(TSymbol) = SizeOf(TSymbolControl), ' ',
          SizeOf(TParam) = SizeOf(TParamControl));
  o.Free;
end.

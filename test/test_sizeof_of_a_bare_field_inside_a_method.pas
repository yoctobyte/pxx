{ SizeOf was the ONE intrinsic taking a name that never learned implicit Self.
  Length, Low, High, Ord, Assigned, Inc and FillChar all resolve a bare `FBuf`
  inside a method against Self; SizeOf answered `unknown type or variable`,
  while `SizeOf(Self.FBuf)` on the very same field was correct. Two spellings
  of one question, and only one of them worked -- fcl-passrc pscanner.pp:2338
  (`SetTextBuf(FTextFile, FBuffer, SizeOf(FBuffer))`) is the call.

  The rows are chosen so a wrong answer is a DIFFERENT NUMBER and not a
  refusal: an array field (RecFieldType answers its ELEMENT kind, so a naive
  fix reports 1 rather than 16), a record field, a scalar, a frozen string, and
  an INHERITED field. The last two rows are the controls that must NOT change:
  a FIELD shadows an outer variable of the same name (fpc's rule, and the one
  Length already applied while SizeOf answered about the global), and the
  qualified spelling keeps its old answer.
  bug-p-sizeof-of-a-bare-field-is-the-one-intrinsic-that-never-learned-implicit-self }
{$mode objfpc}
program test_sizeof_of_a_bare_field_inside_a_method;
type
  TR = record A, B: Integer; end;
  TBase = class
    FInherited: array[0..7] of Integer;
  end;
  TC = class(TBase)
    FBuf: array[0..15] of Byte;
    FR: TR;
    FI: Integer;
    FS: String[9];
    FShadow: array[0..99] of Byte;
    procedure Show;
  end;

procedure TC.Show;
begin
  WriteLn('buf=',   SizeOf(FBuf));
  WriteLn('rec=',   SizeOf(FR));
  WriteLn('int=',   SizeOf(FI));
  WriteLn('str=',   SizeOf(FS));
  WriteLn('inh=',   SizeOf(FInherited));
  { the outer var of a field's name: the FIELD wins, as it does for Length }
  WriteLn('shadow=', SizeOf(FShadow), ' ', Length(FShadow));
  WriteLn('qual=',  SizeOf(Self.FBuf), ' ', SizeOf(Self.FShadow));
end;

var
  FShadow: array[0..3] of Byte;   { same name as a field, at unit scope }
  c: TC;
begin
  FShadow[0] := 0;
  c := TC.Create;
  c.Show;
  WriteLn('outside=', SizeOf(c.FBuf), ' ', SizeOf(FShadow));
end.

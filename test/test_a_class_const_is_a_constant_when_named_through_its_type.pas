program test_a_class_const_is_a_constant_when_named_through_its_type;
{ `TFoo.K` -- a class or record const reached through its OWNING TYPE -- in a
  CONSTANT expression. The folder knew three BARE spellings and not this one, so
  `const G = TObj.Val` answered `not a constant` and the same reference inside
  the class body desynced the member loop with `this token is not a class
  member`. tclass13d.pp is the corpus row. }
{$mode delphi}
type
  TObj = class
  const
    Val = 1;
    Flag = True;
    Letter = 'z';
    V1: Integer = Val;
    V2: Integer = TObj.Val;
  end;

  TSub = class(TObj)
  const
    Own = TObj.Val + 40;
  end;

  TRec = record
  const
    RVal = 2;
    R2: Integer = TRec.RVal;
  end;

const
  G = TObj.Val + 10;
  GF = TObj.Flag;
  GL = TObj.Letter;
  GR = TRec.RVal * 3;
  GS = TSub.Val + 100;       { inherited, named through the SUBCLASS }

var
  arr: array[0..TObj.Val] of Integer;
  brr: array[TRec.RVal..TRec.RVal + 2] of Integer;

begin
  WriteLn('1 ', G);
  WriteLn('2 ', GF);
  WriteLn('3 ', GL);
  WriteLn('4 ', GR);
  WriteLn('5 ', GS);
  WriteLn('6 ', Low(arr), ' ', High(arr));
  WriteLn('7 ', Low(brr), ' ', High(brr));
  WriteLn('8 ', TObj.V1, ' ', TObj.V2);
  WriteLn('9 ', TRec.R2, ' ', TSub.Own);
end.

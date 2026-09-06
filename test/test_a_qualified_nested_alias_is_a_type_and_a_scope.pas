program test_a_qualified_nested_alias_is_a_type_and_a_scope;
{ `TOwner.TNested` is one spelling and it must mean the same thing in every
  position a type name can stand: a declaration, a bounds intrinsic, and the
  left of a constructor call. It did not. `var v: TTest.TRange` compiled while
  `Low(TTest.TRange)` answered `class method not found (TRange)`, and
  `TTest.TP.Create` answered the same thing about TP -- one diagnostic, three
  sites, and NOT one defect: the bounds folders never stripped the qualifier at
  all, while the two constructor walks stripped it and then asked the wrong
  table. Fixing the bounds half left the constructor half failing exactly as
  before, which is how that was established rather than assumed.

  ROWS A..D ARE THE CONTROLS AND THEY WERE ALL GREEN BEFORE THE FIX. The
  unqualified alias, the nested CLASS through both constructor spellings, and
  the unqualified subrange bounds. A test with only the broken rows in it
  cannot tell this fix from a fix that broke aliases, nesting or Low/High in
  general.
  bug-p-a-qualified-nested-alias-is-invisible-to-low-high-and-a-constructor }
{$mode objfpc}{$H+}
type
  TThing = class
    V: Integer;
    constructor Create;
    constructor Make;
  end;
  TQ = TThing;                  { unqualified alias to a class -- always worked }
  TFree = 1..9;                 { unqualified subrange      -- always worked }
  TTest = class
  type
    TRange = 1..9;
    TCol   = (cRed, cGreen, cBlue);
    TInner = class
      W: Integer;
      constructor Create;
      constructor Make;
    end;
    TP = TThing;                { the alias, INSIDE a class body }
  end;

constructor TThing.Create; begin V := 2; end;
constructor TThing.Make;   begin V := 1; end;
constructor TTest.TInner.Create; begin W := 4; end;
constructor TTest.TInner.Make;   begin W := 3; end;

var
  a, b: TTest.TInner;
  c, d: TThing;
  e: TQ;
  r: TTest.TRange;
begin
  { controls }
  e := TQ.Make;                  WriteLn('A: ', e.V);            e.Free;
  a := TTest.TInner.Create;      WriteLn('B: ', a.W);            a.Free;
  b := TTest.TInner.Make;        WriteLn('C: ', b.W);            b.Free;
  WriteLn('D: ', Low(TFree), ' ', High(TFree));

  { the qualified nested alias as a CONSTRUCTOR scope }
  c := TTest.TP.Create;          WriteLn('E: ', c.V);            c.Free;
  d := TTest.TP.Make;            WriteLn('F: ', d.V);            d.Free;

  { the qualified nested subrange and enum as a TYPE in the bounds intrinsics }
  WriteLn('G: ', Low(TTest.TRange), ' ', High(TTest.TRange));
  WriteLn('H: ', Ord(Low(TTest.TCol)), ' ', Ord(High(TTest.TCol)));
  WriteLn('I: ', SizeOf(TTest.TRange));
  r := 3;
  WriteLn('J: ', r);
end.

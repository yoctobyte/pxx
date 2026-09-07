program test_a_system_qualified_name_beats_a_shadowing_class_member;
{ `System.X` IS THE DOCUMENTED WAY TO REACH THE RTL DECLARATION WHEN SOMETHING
  SHADOWS THE NAME, and inside a CLASS METHOD it did not work: the class's own
  member won anyway. rtl-generics is where this bites -- `TCompare` declares
  `class function Integer(constref ALeft, ARight: Integer): Integer` and its
  `UInt8` writes `System.Integer(ALeft)` -- and it is the wall for both
  generics.defaults and Generics.Collections.

  ONE CHARACTER. ConsumeUnitQualifier answers -1 unqualified, >= 0 for a named
  unit, and -2 for `System.`. The static-method dispatch guarded on `qUnit < 0`,
  which READS as "not unit-qualified" and admits the System marker -- the one
  qualifier that exists precisely to refuse a same-named member. Its sibling
  guards spell it `= -1`.

  ROWS 1 AND 2 ARE THE SAME DEFECT WEARING TWO FACES AND ROW 2 IS WHY THIS IS A
  BUG AND NOT A DIAGNOSTIC GAP. With MISMATCHED arity the shadow cannot be
  called and the compiler refuses -- `expected ',' before ')'`, the parser asking
  for the shadow's second argument, which is its own diagnosis. With MATCHING
  arity there is nothing to refuse: it COMPILES and returns the method's value.
  Measured on pin v407: row 1 refuses, row 2 prints 0. A silent wrong answer is
  what let this reach a released compiler.

  THE SHADOW RETURNS 4242 ON PURPOSE. It must not return anything the cast could
  also produce -- a shadow returning the argument, or 0, would make the wrong
  binding print the right answer for rows built out of small numbers.

  ROWS 3 AND 4 ARE CONTROLS FOR WHAT WAS *NOT* BROKEN, and both were measured on
  the pin before being written down. Row 3: the same shadow declared as an
  INSTANCE method resolves correctly on the pin, so the instance dispatch arm
  never had this hole and no guard was added there for symmetry. Row 4: the same
  construct OUTSIDE any method compiles on the pin, so `System.`-qualified
  typecasts are not broken in general -- only the case the qualifier exists for.

  ROW 5 IS DELIBERATELY NOT `SizeOf(System.Integer)`, AND THE OBVIOUS ASSERTION
  WAS REJECTED RATHER THAN OVERLOOKED. FPC's `System.Integer` is SmallInt: the
  4-byte Integer comes from the MODE. So `SizeOf(System.Integer)` is 2 under FPC
  and 4 here (compat-p-system-integer-is-smallint-in-fpc), and a row asserting 4
  would pass, would match the corpus program that motivated the whole ticket,
  and would encode a rule FPC does not have. `System.LongWord` agrees under both,
  so its answer cannot be reached by accident. Do not "simplify" this back.

  Oracle: fpc 3.2.2 prints all five rows exactly as below.
  bug-p-the-system-qualifier-is-stripped-rather-than-resolved-so-a-shadowing-member-wins }
{$mode delphi}
type
  TCompare = class
    { the SHADOWS -- same names as builtin types, which is legal and is what
      rtl-generics does }
    class function Integer(constref ALeft, ARight: Integer): LongInt;
    class function LongWord(constref A: Byte): LongInt;
    class function ArityMatch(constref A: Byte): LongInt;
    { the callers }
    class function UInt8Wide(constref ALeft, ARight: Byte): LongInt;
    class function UInt8Same(constref ALeft, ARight: Byte): LongInt;
    class function Width: LongInt;
  end;

  TBox = class
    function Integer(constref A: Byte): LongInt;      { an INSTANCE shadow }
    function Diff(constref L, R: Byte): LongInt;
  end;

class function TCompare.Integer(constref ALeft, ARight: Integer): LongInt;
begin Result := 4242; end;

class function TCompare.LongWord(constref A: Byte): LongInt;
begin Result := 4242; end;

class function TCompare.ArityMatch(constref A: Byte): LongInt;
begin Result := 4242; end;

{ 1: the shadow takes TWO arguments and the cast passes one -- the REFUSAL face }
class function TCompare.UInt8Wide(constref ALeft, ARight: Byte): LongInt;
begin Result := System.Integer(ALeft) - System.Integer(ARight); end;

{ 2: the shadow takes ONE argument, exactly what the cast passes -- the SILENT
     face. Nothing here can refuse; a wrong binding just returns 4242. }
class function TCompare.UInt8Same(constref ALeft, ARight: Byte): LongInt;
begin Result := System.LongWord(ALeft) - System.LongWord(ARight); end;

class function TCompare.Width: LongInt;
begin Result := SizeOf(System.LongWord); end;

function TBox.Integer(constref A: Byte): LongInt;
begin Result := 4242; end;

function TBox.Diff(constref L, R: Byte): LongInt;
begin Result := System.Integer(L) - System.Integer(R); end;

var
  b: TBox;
  x, y: Byte;
  outside: LongInt;
begin
  x := 200; y := 44;
  WriteLn('classwide  = ', TCompare.UInt8Wide(x, y));
  WriteLn('classsame  = ', TCompare.UInt8Same(x, y));
  b := TBox.Create;
  WriteLn('instance   = ', b.Diff(x, y));
  outside := System.Integer(x) - System.Integer(y);
  WriteLn('outside    = ', outside);
  WriteLn('sizeof-lw  = ', TCompare.Width);
end.

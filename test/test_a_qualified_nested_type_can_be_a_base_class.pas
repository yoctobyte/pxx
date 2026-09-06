program test_a_qualified_nested_type_can_be_a_base_class;
{ `class(TOuter.TInner)` -- a QUALIFIED NESTED TYPE in the ANCESTOR position.
  Every other position already took the spelling (`var n: tc.tnest`,
  `tc.tnest.Create`, SizeOf, Default, Low/High); the ancestor list read ONE
  identifier and handed the `.` to its own Expect(')'), so tclass13a.pp answered
  `expected ')' before '.'` -- the parenthesis blamed for a name that was never
  looked up. Row 2 is the corpus shape: a nested class whose bare NAME collides
  with the one it derives from. Row 4 is the control that must NOT change: a
  sibling nested type named UNQUALIFIED from inside the owner's own body, which
  is the only place fpc lets the bare spelling reach it. }
{$mode delphi}
type
  tc = class
   type
    tnest = class
      function Who: Integer; virtual;
    end;
    tsib = class(tnest)          { unqualified, from INSIDE the owner body }
      function Who: Integer; override;
    end;
    tdeep = class
     type
      tinner = class
        function Depth: Integer;
      end;
    end;
  end;

  { the corpus row: td.tnest derives from tc.tnest and shares its bare name }
  td = class(tc)
   type
     tnest = class(tc.tnest)
       function Who: Integer; override;
     end;
  end;

  { two hops }
  te = class(tc.tdeep.tinner)
    function Extra: Integer;
  end;

function tc.tnest.Who: Integer; begin Result := 1; end;
function tc.tsib.Who: Integer; begin Result := 4; end;
function tc.tdeep.tinner.Depth: Integer; begin Result := 2; end;
function td.tnest.Who: Integer; begin Result := 3; end;
function te.Extra: Integer; begin Result := Depth + 10; end;

var
  a: tc.tnest;
  b: td.tnest;
  c: te;
  d: tc.tsib;
begin
  a := tc.tnest.Create;
  b := td.tnest.Create;
  c := te.Create;
  d := tc.tsib.Create;
  WriteLn('1 ', a.Who);
  WriteLn('2 ', b.Who);
  WriteLn('3 ', c.Depth, ' ', c.Extra);
  WriteLn('4 ', d.Who);
  { the derived nested class IS its ancestor's nested class, and not the reverse.
    `is` and `as` are the OTHER two positions that read a class name without
    routing through ParseTypeKind, and neither took the qualified spelling. }
  WriteLn('5 ', b is tc.tnest, ' ', a is td.tnest);
  WriteLn('6 ', (b as tc.tnest).Who, ' ', (b as td.tnest).Who);
  a.Free; b.Free; c.Free; d.Free;
end.

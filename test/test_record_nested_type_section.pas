program test_record_nested_type_section;
{ A record may open a nested `type` section, exactly as a class may.
  It was the only structured type that could not: the `type` keyword fell
  through to the field parser, which then demanded a ':' after the name it
  thought it had read. The generic-record family (fpc-testsuite tgeneric63/64)
  failed here, not in the generics machinery.

  Also covers the second half: a record body now claims the types declared in
  it (ParsingClassBodyCi), so FindNestedType can see them and the out-of-line
  `function TOuter.TSub.M` implementation header can walk into the scope.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode delphi}
{$modeswitch advancedrecords}
type
  TOuterR = record
  type
    TAlias  = Integer;
    TSubRec = record
      A, B: Integer;
      function Sum: Integer;
      class function Make(x, y: Integer): TSubRec; static;
    end;
    TSubCls = class
      V: Integer;
      function Twice: Integer;
    end;
    TColour = (clRed, clGreen, clBlue);
  var
    X: Integer;
    N: TSubRec;
  const
    Tag = 77;
    function Total: Integer;
  end;

  { The same nested names in a SECOND record: two distinct scopes, and the
    bare name must keep binding to the first declaration. }
  TOtherR = record
  type
    TSubRec = record
      Q: Integer;
      function Sum: Integer;
    end;
  var
    Y: Integer;
  end;

  { A class nesting a record that itself nests a type -- the walk loops. }
  TDeep = class
  type
    TMid = record
    type
      TLeaf = record
        L: Integer;
        function Get: Integer;
      end;
    var
      M: Integer;
    end;
  end;

function TOuterR.TSubRec.Sum: Integer;
begin Result := A + B; end;

class function TOuterR.TSubRec.Make(x, y: Integer): TSubRec;
begin Result.A := x; Result.B := y; end;

function TOuterR.TSubCls.Twice: Integer;
begin Result := V * 2; end;

function TOuterR.Total: Integer;
begin Result := X + N.Sum; end;

function TOtherR.TSubRec.Sum: Integer;
begin Result := Q * 10; end;

function TDeep.TMid.TLeaf.Get: Integer;
begin Result := L + 1; end;

var
  r: TOuterR;
  o: TOtherR;
  s: TOuterR.TSubRec;
  t: TOtherR.TSubRec;
  c: TOuterR.TSubCls;
  a: TOuterR.TAlias;
  cl: TOuterR.TColour;
  lf: TDeep.TMid.TLeaf;
  md: TDeep.TMid;
begin
  r.X := 5;
  r.N.A := 1; r.N.B := 2;
  WriteLn('total=', r.Total);
  WriteLn('tag=', TOuterR.Tag);

  s := TOuterR.TSubRec.Make(10, 20);
  WriteLn('sum=', s.Sum);

  t.Q := 4;
  WriteLn('other=', t.Sum);

  o.Y := 9;
  WriteLn('y=', o.Y);

  c := TOuterR.TSubCls.Create;
  c.V := 21;
  WriteLn('twice=', c.Twice);
  c.Free;

  a := 123;
  WriteLn('alias=', a);
  cl := clBlue;
  WriteLn('colour=', Ord(cl));

  lf.L := 41;
  WriteLn('leaf=', lf.Get);
  md.M := 3;
  WriteLn('mid=', md.M);

  WriteLn('sizes=', SizeOf(TOuterR.TSubRec), ' ', SizeOf(TOtherR.TSubRec));
end.

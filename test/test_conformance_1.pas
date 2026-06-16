program test_conformance_1;

{ Synthetic cross-target conformance harness (feature-synthetic-feature-matrix-test).
  Combines language features the self-host compiler does NOT itself use — classes,
  inheritance, virtual dispatch, properties — mixed with Int64, managed strings,
  records, dynamic arrays, array of const, variants, floats, exceptions, and
  adversarial control flow. Output must be deterministic and identical on every
  target (diffed against the x86-64 oracle). }

type
  PInt64 = ^Int64;
  EMyError = class
    Msg: AnsiString;
  end;
  TShape = class
    Name: AnsiString;
    Sides: Integer;
    constructor Create(aName: AnsiString; aSides: Integer);
    function Area: Double; virtual;
    function Tag: Int64; virtual;
  end;

  TSquare = class(TShape)
    Side: Double;
    constructor Create(aSide: Double);
    function Area: Double; override;
    function Tag: Int64; override;
  end;

  TCircle = class(TShape)
    R: Double;
    constructor Create(aR: Double);
    function Area: Double; override;
  end;

  TPoint = record
    X, Y: Integer;
    Label_: AnsiString;
  end;

constructor TShape.Create(aName: AnsiString; aSides: Integer);
begin
  Name := aName;
  Sides := aSides;
end;

function TShape.Area: Double;
begin
  Area := 0.0;
end;

function TShape.Tag: Int64;
begin
  Tag := 1000000000 + Int64(Sides);
end;

constructor TSquare.Create(aSide: Double);
begin
  inherited Create('square', 4);
  Side := aSide;
end;

function TSquare.Area: Double;
begin
  Area := Side * Side;
end;

function TSquare.Tag: Int64;
begin
  Tag := 5000000000 + Int64(Sides);
end;

constructor TCircle.Create(aR: Double);
begin
  inherited Create('circle', 0);
  R := aR;
end;

function TCircle.Area: Double;
begin
  Area := 3.0 * R * R;
end;

procedure DumpVarRec(const items: array of const);
var i: Integer; p: PChar;
begin
  for i := 0 to Length(items) - 1 do
  begin
    if items[i].VType = vtInteger then writeln('  i ', items[i].VInteger)
    else if items[i].VType = vtInt64 then writeln('  q ', PInt64(items[i].VInt64)^)
    else if items[i].VType = vtBoolean then writeln('  b ', items[i].VBoolean)
    else if items[i].VType = vtAnsiString then
    begin
      p := PChar(items[i].VAnsiString); write('  s ');
      while p^ <> Chr(0) do begin write(p^); p := PChar(Pointer(p) + 1); end;
      writeln;
    end
    else writeln('  ? ', items[i].VType);
  end;
end;


var
  shapes: array[0..2] of TShape;
  err: EMyError;
  i: Integer;
  total: Double;
  pts: array of TPoint;
  v: Variant;
  caught: Integer;
  s: AnsiString;

begin
  shapes[0] := TSquare.Create(3.0);
  shapes[1] := TCircle.Create(2.0);
  shapes[2] := TShape.Create('generic', 7);

  total := 0.0;
  for i := 0 to 2 do
  begin
    write('shape ', i, ' ', shapes[i].Name, ' area=');
    writeln(shapes[i].Area:0:2, ' tag=', shapes[i].Tag);
    total := total + shapes[i].Area;
  end;
  writeln('total area=', total:0:2);

  { dynamic array of records, with a managed string field }
  SetLength(pts, 3);
  for i := 0 to 2 do
  begin
    pts[i].X := i * 2;
    pts[i].Y := i * i;
    pts[i].Label_ := 'p';
  end;
  writeln('pts len=', Length(pts), ' high=', High(pts));
  for i := 0 to High(pts) do
    writeln('  pt ', pts[i].Label_, ' ', pts[i].X, ',', pts[i].Y);

  { array of const mixing types }
  DumpVarRec([42, Int64(9000000000), True, 'mixed']);

  { variant }
  v := 123;
  writeln('v int=', Integer(v));
  v := 'hello';

  { exceptions }
  caught := 0;
  err := EMyError.Create;
  err.Msg := 'boom';
  try
    raise err;
  except
    on E: EMyError do
    begin
      caught := 1;
      writeln('caught: ', E.Msg);
    end;
  end;
  writeln('caught=', caught);

  { string ops + case }
  s := 'abc';
  s := s + 'def';
  writeln('concat=', s, ' len=', Length(s));
  for i := 1 to Length(s) do
    case s[i] of
      'a', 'e': write('V');
    else write('.');
    end;
  writeln;
end.

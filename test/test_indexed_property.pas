program test_indexed_property;
{ Indexed (array) properties + `default` — feature-indexed-array-properties. }
type
  TList = class
    FI: array of Integer;
    procedure Setup;
    function GetItem(i: Integer): Integer;
    procedure SetItem(i: Integer; v: Integer);
    property Items[i: Integer]: Integer read GetItem write SetItem; default;
  end;

  TRO = class
    FI: array of Integer;
    procedure Setup;
    function G(i: Integer): Integer;
    property Vals[i: Integer]: Integer read G;   { read-only, non-default }
  end;

  TGrid = class
    FC: array of Integer;
    procedure Setup;
    function GetCell(a, b: Integer): Integer;
    procedure SetCell(a, b: Integer; v: Integer);
    property Cells[a, b: Integer]: Integer read GetCell write SetCell; default;
  end;

procedure TList.Setup; begin SetLength(FI, 4); end;
function TList.GetItem(i: Integer): Integer; begin GetItem := FI[i]; end;
procedure TList.SetItem(i: Integer; v: Integer); begin FI[i] := v; end;

procedure TRO.Setup; begin SetLength(FI, 3); FI[0] := 10; FI[1] := 20; FI[2] := 30; end;
function TRO.G(i: Integer): Integer; begin G := FI[i]; end;

procedure TGrid.Setup; begin SetLength(FC, 9); end;
function TGrid.GetCell(a, b: Integer): Integer; begin GetCell := FC[a * 3 + b]; end;
procedure TGrid.SetCell(a, b: Integer; v: Integer); begin FC[a * 3 + b] := v; end;

var
  L: TList;
  r: TRO;
  g: TGrid;
begin
  L := TList.Create;
  L.Setup;
  L.Items[2] := 99;     { indexed setter }
  L.Items[0] := 7;
  L[1] := 42;           { default setter }
  writeln(L.Items[2]);  { 99 — indexed getter }
  writeln(L[0]);        { 7  — default getter }
  writeln(L[1]);        { 42 }

  r := TRO.Create;
  r.Setup;
  writeln(r.Vals[0]);   { 10 — read-only indexed getter }
  writeln(r.Vals[2]);   { 30 }

  g := TGrid.Create;
  g.Setup;
  g.Cells[1, 2] := 55;  { multi-index setter }
  g[2, 0] := 88;        { default multi-index setter }
  writeln(g.Cells[1, 2]); { 55 — multi-index getter }
  writeln(g[2, 0]);     { 88 — default multi-index getter }
end.

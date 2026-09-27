{ DELPHI-MODE TWIN of test_with_reaches_a_helper_member.pas.

  A BARE NAME INSIDE `with x do` REACHES A HELPER OF x, AS `x.Name` DOES.
  `with c do WriteLn(Two)` over `class helper for TC` declaring Two was
  "undefined variable (Two)": the with loop asked the operand's own fields,
  properties and methods and never its helpers. Every helper kind failed --
  class helper, record helper on a plain or an advanced record, method or
  property -- while the dotted spelling of each worked. Found by franks-a3.
  Expected output is FPC 3.2.2's, generated, not written.
  bug-p-with-rec-do-a-helper-member-is-undefined

  Found with it, and wrong DOTTED as well (v445 too): a helper for TBase that
  declares Own lost to TBase.Own on a TDerived receiver (`d.Own` 1, FPC 100),
  because ClassHelperRecFor asked "does the class have the name" through
  finders that walk the parents, where FPC's rule is "does THIS class declare
  it"; and a class-helper PROPERTY was "no such member" (`c.Dbl`).

  Record-helper bodies spell Self.a: the bare-field form inside a record
  helper's own body is a separate defect, fixed in its own commit. }
program test_with_reaches_a_helper_member_delphi;
{$mode delphi}
type
  TBase = class
    v: Integer;
    function Own: Integer;
    function Kept: Integer;
  end;
  TDerived = class(TBase)
  end;
  TBaseH = class helper for TBase
    function Two: Integer;
    function Add(n: Integer): Integer; overload;
    function Add(n, m: Integer): Integer; overload;
    procedure Bump(n: Integer);
    function Own: Integer;                  { shadows the class's own }
    function GetH: Integer;
    procedure SetH(x: Integer);
    property Dbl: Integer read Two;
    property H: Integer read GetH write SetH;
  end;
  TR = record a, b: Integer; end;
  PR = ^TR;
  TRH = record helper for TR
    function Sum: Integer;
    procedure SetA(x: Integer);
    property S: Integer read Sum;
  end;
  TAdv = record
    x: Integer;
    function Mine: Integer;
  end;
  TAdvH = record helper for TAdv
    function Twice: Integer;
  end;

function TBase.Own: Integer; begin Result := 1; end;
function TBase.Kept: Integer; begin Result := 5; end;
function TBaseH.Two: Integer; begin Result := v * 2; end;
function TBaseH.Add(n: Integer): Integer; begin Result := v + n; end;
function TBaseH.Add(n, m: Integer): Integer; begin Result := v + n * m; end;
procedure TBaseH.Bump(n: Integer); begin v := v + n; end;
function TBaseH.Own: Integer; begin Result := 100 + v; end;
function TBaseH.GetH: Integer; begin Result := v - 1; end;
procedure TBaseH.SetH(x: Integer); begin v := x + 1; end;
function TRH.Sum: Integer; begin Result := Self.a + Self.b; end;
procedure TRH.SetA(x: Integer); begin Self.a := x; end;
function TAdv.Mine: Integer; begin Result := x + 1; end;
function TAdvH.Twice: Integer; begin Result := Self.x * 2; end;

function MakeR(a, b: Integer): TR; begin Result.a := a; Result.b := b; end;

var
  c: TBase; d: TDerived; r: TR; rs: array[0..1] of TR; p: PR; q: TAdv;
begin
  c := TBase.Create; c.v := 4;
  with c do
  begin
    WriteLn('class method   ', Two);
    Bump(3);
    WriteLn('after Bump     ', v, ' ', Two);
    WriteLn('shadows own    ', Own, ' kept ', Kept);
    WriteLn('property       ', Dbl);
    H := 20;
    WriteLn('prop write     ', v, ' ', H);
    WriteLn('overloads      ', Add(1), ' ', Add(2, 3));
    WriteLn('in expression  ', Two + Two * 2);
  end;
  d := TDerived.Create; d.v := 7;
  with d do WriteLn('inherited      ', Two, ' ', Own);
  WriteLn('dotted derived ', d.Own, ' ', d.Kept);

  r.a := 2; r.b := 5;
  with r do
  begin
    WriteLn('record method  ', Sum);
    SetA(10);
    WriteLn('by reference   ', a, ' ', Sum, ' ', S);
  end;
  WriteLn('outside        ', r.a);
  rs[1].a := 7; rs[1].b := 1;
  with rs[1] do begin SetA(20); WriteLn('array element  ', Sum); end;
  WriteLn('outside        ', rs[1].a);
  p := @r;
  with p^ do begin SetA(30); WriteLn('through p^     ', Sum); end;
  WriteLn('outside        ', r.a);
  with MakeR(3, 4) do WriteLn('call operand   ', Sum);

  q.x := 6;
  with q do WriteLn('advanced rec   ', Mine, ' ', Twice);

  with c, r do WriteLn('two operands   ', Two + Sum);
  with r do with c do WriteLn('nested         ', Two, ' ', Sum);
  c.Free; d.Free;
end.

{ A `record helper for` a USER record, found on the receiver (delphi mode).
  Until 2026-09-27 every call below answered '"Bump": no such member on
  this record/class' (ClassHelperRecFor skipped records), and a bare field
  inside the helper body (MoveBy's X) was "undefined variable". Bump must
  change the receiver, not a copy: through a variable, a record field, a
  static and a dynamic array element, a pointer, a var and a const param.
  Expected output is FPC 3.2's. The last row, `with a.pt do Bump`, needs
  frankd-a3's 50329e2988 (a bare name in WITH reaches a helper) as well. }
program test_record_helper_for_a_user_record_delphi;
{$mode delphi}
type
  TPoint = record X, Y: Integer; end;
  TPointHelper = record helper for TPoint
    function Sum: Integer;
    procedure Bump;
    procedure MoveBy(dx, dy: Integer);
    function Scaled(k: Integer): TPoint;
  end;
  THolder = record pt: TPoint; tag: Integer; end;
  THolderC = class pt: TPoint; end;
function TPointHelper.Sum: Integer; begin Result := Self.X + Self.Y; end;
procedure TPointHelper.Bump; begin Inc(Self.X); end;
procedure TPointHelper.MoveBy(dx, dy: Integer); begin X := X + dx; Y := Y + dy; end;
function TPointHelper.Scaled(k: Integer): TPoint; begin Result.X := X * k; Result.Y := Y * k; end;
var p: TPoint; a: THolder; arr: array[0..2] of TPoint; d: array of TPoint;
    pp: ^TPoint; c: THolderC; i: Integer;
procedure ViaVar(var q: TPoint); begin q.Bump; end;
procedure ViaConst(const q: TPoint); begin WriteLn('const ', q.Sum); end;
begin
  p.X := 1; p.Y := 2; p.Bump; WriteLn('plain ', p.Sum, ' ', p.X);
  p.MoveBy(10, 20); WriteLn('moveby ', p.X, ' ', p.Y);
  WriteLn('scaled ', p.Scaled(2).Sum, ' ', p.Scaled(3).X);
  a.pt.X := 5; a.pt.Y := 6; a.pt.Bump; a.pt.Bump; WriteLn('field ', a.pt.Sum, ' ', a.pt.X);
  for i := 0 to 2 do begin arr[i].X := i; arr[i].Y := 10 * i; end;
  arr[1].Bump; WriteLn('elem ', arr[1].Sum, ' ', arr[0].Sum, ' ', arr[2].Sum);
  SetLength(d, 2); d[1].X := 7; d[1].Y := 1; d[1].Bump; WriteLn('dyn ', d[1].Sum);
  pp := @p; pp^.Bump; WriteLn('ptr ', pp^.Sum, ' ', p.X);
  c := THolderC.Create; c.pt.X := 3; c.pt.Bump; WriteLn('clsfield ', c.pt.Sum); c.Free;
  ViaVar(p); WriteLn('var ', p.X); ViaConst(p);
  with a.pt do begin Bump; WriteLn('with ', Sum); end;
end.

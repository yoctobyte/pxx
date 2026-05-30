program test_record_multifield;
{ Multi-name record fields (`X, Y: Integer`) used to fail to parse — the field
  parser read exactly one name before the ':'. Now comma-separated names share
  one type, each laid out at its own offset. Also exercises pointer-to-record
  field indexing with a trailing .field, which needs ResolveNodeRec to map the
  element back to the record (the FindUField calls were missing the
  REC_UCLASS_BASE offset). }
type
  TPt = record X, Y: Integer; end;
  PPt = ^TPt;
  TC = class
  public
    Pts: PPt;
  end;
var
  r: TPt;
  c: TC;
  arr: array[0..2] of TPt;
  i: Integer;
begin
  r.X := 11; r.Y := 22;
  writeln(r.X, ' ', r.Y);                 { 11 22 }

  c := TC.Create;
  c.Pts := @arr[0];
  for i := 0 to 2 do
  begin
    c.Pts[i].X := i;
    c.Pts[i].Y := i * 10;
  end;
  writeln(c.Pts[0].X, ' ', c.Pts[1].X, ' ', c.Pts[2].X);   { 0 1 2 }
  writeln(c.Pts[0].Y, ' ', c.Pts[1].Y, ' ', c.Pts[2].Y);   { 0 10 20 }
end.

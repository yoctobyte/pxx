program TestForInAggrElems;
{$mode objfpc}
type
  TPt = record x, y: Integer; end;
  TBox = class
    v: Integer;
  end;
var
  pts: array of TPt;
  p: TPt;
  boxes: array of TBox;
  b: TBox;
  strs: array of AnsiString;
  s, acc: AnsiString;
  i, sum: Integer;
begin
  { array of record — element copied by value }
  SetLength(pts, 3);
  for i := 0 to 2 do begin pts[i].x := i; pts[i].y := i * 10; end;
  sum := 0;
  for p in pts do sum := sum + p.x + p.y;
  writeln('rec=', sum);          { 33 }

  { array of class — element is a reference }
  SetLength(boxes, 3);
  for i := 0 to 2 do begin boxes[i] := TBox.Create; boxes[i].v := (i + 1) * 5; end;
  sum := 0;
  for b in boxes do sum := sum + b.v;
  writeln('cls=', sum);          { 30 }

  { array of AnsiString — managed element binding (regression: was iterated
    char-by-char because the dynarray TypeKind is the element base type) }
  SetLength(strs, 3);
  strs[0] := 'aa'; strs[1] := 'bb'; strs[2] := 'cc';
  acc := '';
  for s in strs do acc := acc + s;
  writeln('str=', acc);          { aabbcc }
end.

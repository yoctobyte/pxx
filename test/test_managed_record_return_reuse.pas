type TR = record n: Integer; xs: array of Integer; end;
function id(const a: TR): TR;
begin Result := a; end;
function add2(const a, b: TR): TR;
var i: Integer;
begin
  SetLength(Result.xs, Length(a.xs));
  for i := 0 to High(a.xs) do Result.xs[i] := a.xs[i] + b.xs[i];
  Result.n := a.n + b.n;
end;
var r, s, keep: TR; i: Integer;
begin
  SetLength(r.xs, 3);
  for i := 0 to 2 do r.xs[i] := i + 1;
  r.n := 10;
  keep := r;                 { shared handle before overwrite }
  r := id(r);                { dest aliases the argument }
  WriteLn(r.n, ' ', r.xs[0], r.xs[1], r.xs[2]);
  WriteLn(keep.n, ' ', keep.xs[0], keep.xs[1], keep.xs[2]);
  s := r;
  r := add2(r, r);           { dest aliases both args }
  WriteLn(r.n, ' ', r.xs[0], r.xs[1], r.xs[2]);
  WriteLn(s.n, ' ', s.xs[0], s.xs[1], s.xs[2]);
  for i := 1 to 50000 do r := add2(id(s), s);  { loop reuse }
  WriteLn(r.n, ' ', r.xs[0], r.xs[1], r.xs[2]);
end.

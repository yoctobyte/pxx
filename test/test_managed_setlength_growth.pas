program test_managed_setlength_growth;

{$define PXX_MANAGED_STRING}

var
  s: AnsiString;
  i: Integer;

procedure GrowVar(var t: AnsiString; n: Integer);
begin
  SetLength(t, n);
  t[n] := Chr(Ord('a') + (n mod 26));
end;

begin
  s := '';
  for i := 1 to 20000 do
  begin
    SetLength(s, i);
    s[i] := Chr(Ord('a') + (i mod 26));
  end;
  if Length(s) = 20000 then writeln(1) else writeln(0);
  if s[1] = 'b' then writeln(1) else writeln(0);
  if s[20000] = Chr(Ord('a') + (20000 mod 26)) then writeln(1) else writeln(0);
  SetLength(s, 5);
  if (Length(s) = 5) and (s[5] = Chr(Ord('a') + (5 mod 26))) then writeln(1) else writeln(0);
  SetLength(s, 12);
  if (Length(s) = 12) and (s[6] = #0) and (s[12] = #0) then writeln(1) else writeln(0);

  s := '';
  for i := 1 to 20000 do
    GrowVar(s, i);
  if Length(s) = 20000 then writeln(1) else writeln(0);
  if s[1] = 'b' then writeln(1) else writeln(0);
  if s[20000] = Chr(Ord('a') + (20000 mod 26)) then writeln(1) else writeln(0);
end.

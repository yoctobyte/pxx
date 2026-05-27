program TestStrictOverloadError;

{$strict_overload on}

procedure Select(x: Integer);
begin
  writeln(x);
end;

procedure Select(c: Char);
begin
  writeln(Ord(c));
end;

begin
  Select(1);
end.

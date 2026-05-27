program TestStrictOverload;

{$strict_overload on}

function Pick(x: Integer): Integer; overload;
begin
  Pick := x + 1;
end;

function Pick(c: Char): Integer; overload;
begin
  Pick := Ord(c);
end;

begin
  writeln(Pick(4));
  writeln(Pick('A'));
end.

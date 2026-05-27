program TestOverloading;

procedure PrintVal(x: Integer); overload;
begin
  writeln('Integer: ', x);
end;

procedure PrintVal(c: Char); overload;
begin
  writeln('Char: ', c);
end;

procedure PrintVal(x, y: Integer); overload;
begin
  writeln('Two Integers: ', x, ', ', y);
end;

function Add(a, b: Integer): Integer; overload;
begin
  Result := a + b;
end;

function Add(a, b: Char): String; overload;
begin
  Result := 'Char addition: ' + a + b;
end;

begin
  PrintVal(42);
  PrintVal('A');
  PrintVal(10, 20);

  writeln('Add integers: ', Add(5, 7));
  writeln(Add('X', 'Y'));
end.

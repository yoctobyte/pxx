{$CASESENSITIVE ON}
program TestCaseSensitive;

var Value, value: Integer;

procedure Show;
begin
  writeln('upper');
end;

procedure show;
begin
  writeln('lower');
end;

begin
  Value := 10;
  value := 20;
  writeln(Value);
  writeln(value);
  Show;
  show;
end.

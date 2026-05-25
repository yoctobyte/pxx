program Records;

type
  TFixup = record
    CodePos: Integer;
    DataOff: Integer;
  end;

var
  f: TFixup;
  a: array[0..1] of TFixup;

begin
  f.CodePos := 42;
  f.DataOff := 7;
  writeln(f.CodePos);
  writeln(f.DataOff);

  a[0].CodePos := 11;
  a[1].DataOff := 22;
  writeln(a[0].CodePos);
  writeln(a[1].DataOff);
end.

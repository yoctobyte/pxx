{$define PXX_MANAGED_STRING}
program test_managed_exception_cleanup;

procedure FailWithManagedLocals;
var
  s: AnsiString;
  a: array of AnsiString;
begin
  SetLength(s, 65536);
  s[1] := 'x';
  SetLength(a, 8);
  a[0] := s;
  a[7] := 'tail';
  raise 7;
end;

var
  i, caught: Integer;

begin
  caught := 0;
  for i := 1 to 9000 do
  begin
    try
      FailWithManagedLocals;
    except
      Inc(caught);
    end;
  end;
  if caught = 9000 then
    writeln(1)
  else
    writeln(0);
end.

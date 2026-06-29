program test_builtin_name_params;

function Foo(Chr: Char): Integer;
begin
  if Chr = 'A' then Foo := 1 else Foo := 0;
end;

function AddOrd(Ord: Integer): Integer;
begin
  AddOrd := Ord + 1;
end;

procedure AddLength(Length: Integer; var OutValue: Integer);
begin
  OutValue := Length + 2;
end;

var n: Integer;
begin
  WriteLn(Foo('A'));
  WriteLn(AddOrd(40));
  AddLength(5, n);
  WriteLn(n);
  WriteLn(Chr(66));
  WriteLn(Ord('C'));
end.

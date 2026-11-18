{ A label inside a finally body: the body is lowered once per path that runs
  it (fall-through, handler, each exit/continue that crosses it), and each copy
  needs its own label ids. FPC prints 4, 24, 6.
  bug-a-a-label-inside-a-finally-body-is-a-duplicate-ir-label }
program test_goto_label_in_finally_body;
{$mode objfpc}
uses SysUtils;
function F1: Integer;
label l;
begin
  Result := 0;
  try
    Result := 1;
  finally
    goto l;
    Result := -1;
    l:
    Result := Result + 3;
  end;
end;
function F2(n: Integer): Integer;
label again;
var i: Integer;
begin
  Result := 0;
  for i := 1 to n do
  begin
    try
      if i = 2 then Continue;
      if i = 4 then Exit;
      Result := Result + 10;
    finally
      again:
      Result := Result + 1;
      if Result mod 7 = 0 then goto again;
    end;
  end;
end;
function F3: Integer;
label l;
begin
  Result := 0;
  try
    try
      raise Exception.Create('x');
    finally
      goto l;
      Result := 100;
      l:
      Result := Result + 5;
    end;
  except
    Result := Result + 1;
  end;
end;
begin
  WriteLn(F1);
  WriteLn(F2(5));
  WriteLn(F3);
end.

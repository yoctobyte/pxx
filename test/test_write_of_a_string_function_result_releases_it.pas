program test_write_of_a_string_function_result_releases_it;
{ Write(F(x)) with F returning an AnsiString: the write owns the result and
  used to release only a concat, so this leaked one block per call on every
  backend (179 of 200 live on x86-64). Run under -dPXX_ALLOC_CENSUS with a
  leak bound in the Makefile. One line per iteration: the census lines it
  prints on stderr must start a line for assert_no_leak to read them. }
{$mode objfpc}
uses SysUtils;

function F(k: Integer): AnsiString;
begin
  Result := 'v';
  Result := Result + Chr(65 + k mod 20);
end;

var k: Integer;
begin
  for k := 1 to 300 do
  begin
    Write(F(k));
    Write(IntToStr(k * 1000));
    WriteLn(F(k) + '.');
  end;
end.

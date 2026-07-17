program test_ptr_deref_string_index;
{ Regression for bug-pascal-ptr-deref-string-index: char-indexing a string
  through a pointer-to-string deref (p^[k]) must read the chars, not the handle. }
procedure R;
var s: AnsiString; p: ^AnsiString; i, err: Integer;
begin
  s := 'ABCDE'; p := @s; err := 0;
  for i := 1 to 5 do
    if Ord(p^[i]) <> 64 + i then Inc(err);   { A=65..E=69 }
  if (Length(p^) = 5) and (p^ = 'ABCDE') and (err = 0) then writeln('PTRSTRIDX OK')
  else writeln('PTRSTRIDX FAIL err=', err);
end;
begin R; end.

program test_cast_deref_varparam;
{ Cast-deref (`PChar(s)^`) as a by-ref/untyped argument, METHOD-call path
  (bug-cast-deref-as-varparam-arg). The plain-proc path is covered by
  test_ptr_untyped_deref.pas. }
uses classes;
var
  st: TMemoryStream;
  s, r: AnsiString;
  x: Integer;
begin
  st := TMemoryStream.Create;
  s := 'abc';
  st.Write(PChar(s)^, Length(s));
  st.Position := 0;
  r := 'zzz';
  x := st.Read(PChar(r)^, 3);
  writeln(r, ' ', x);
  st.Free;
end.

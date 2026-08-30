program test_header_static_body_c;
uses hdrstatic_c;
begin
  writeln(hs_plain());
  writeln(hs_inline(41));
end.

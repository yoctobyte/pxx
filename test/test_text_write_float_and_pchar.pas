program test_text_write_float_and_pchar;

{$mode objfpc}

{ A write through a Text VARIABLE -- Output, a Text-typed StdErr, a real file
  -- must print exactly what the console path and FPC print. It printed a
  float with no decimals in natural form (`2.25` where FPC prints
  ` 2.2500000000000000E+000`), a Single the same, `d:12` as padded natural
  form, and a PChar as its ADDRESS, on every target. `Str` and a VARIABLE
  field width share the same formatter (TextStrArg), so they are checked here
  too. Every line is compared against FPC 3.2.2.
  bug-a-a-text-write-prints-a-bare-float-in-natural-form-and-a-pchar-as-its-address }

var
  d, z, big, tiny, sub, carry: Double;
  sg: Single;
  p, pn: PChar;
  f: Text;
  s: AnsiString;
  w: Integer;
begin
  d := 2.25; z := 0.0; big := 1.5e300; tiny := -3.25e-300; sub := 5e-324;
  carry := 9.99999999999999999; sg := 1.5; p := 'pchar'; pn := nil; w := 14;

  WriteLn(Output, '[', d, '][', -d, '][', z, '][', -z, ']');
  WriteLn(Output, '[', d:12, '][', d:8, '][', d:30, ']');
  WriteLn(Output, '[', d:0:2, '][', d:9:3, ']');
  WriteLn(Output, '[', big, '][', tiny, '][', sub, '][', carry, ']');
  WriteLn(Output, '[', sg, '][', sg:12, '][', sg:0:3, ']');
  WriteLn(Output, '[', p, '][', p:8, '][', pn, ']');
  WriteLn(Output, '[', d:w, '][', sg:w, ']');

  WriteLn('[', d:w, '][', sg:w, '][', d:w:2, ']');

  Str(d, s); WriteLn('Str [', s, ']');
  Str(d:12, s); WriteLn('Str [', s, ']');
  Str(sg, s); WriteLn('Str [', s, ']');
  Str(d:0:3, s); WriteLn('Str [', s, ']');

  WriteLn(StdErr, '[', d, '][', p, '][', sg, ']');

  Assign(f, 'test_text_write_float_and_pchar.tmp');
  Rewrite(f);
  WriteLn(f, '[', d, '][', d:12, '][', sg, '][', p, '][', p:7, ']');
  Close(f);
  Assign(f, 'test_text_write_float_and_pchar.tmp');
  Reset(f);
  ReadLn(f, s);
  Close(f);
  Erase(f);
  WriteLn('file ', s);
end.

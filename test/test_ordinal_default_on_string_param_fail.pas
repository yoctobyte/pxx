{ %FAIL-style negative: an ordinal default on a STRING parameter.

  This used to compile clean and SEGFAULT on the omitted argument — the bare
  ordinal reached the callee as a string pointer, and the crash landed wherever
  the string was first touched, nowhere near the declaration. The default's
  shape was chosen from the LITERAL's token kind and never checked against the
  parameter's declared type. FPC rejects it; so do we.
  bug-p-integer-default-on-a-string-parameter-is-accepted-and-segfaults }
program test_ordinal_default_on_string_param_fail;
procedure R(s: AnsiString = 1);
begin
  writeln('[', s, ']');
end;
begin
  R();
end.

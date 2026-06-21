{ Regression: bare string Copy(s, index[, count]) with NO `uses` — lowered to the
  __pxxStrCopy builtin substring helper. The dynarray Copy and the explicit
  `uses sysutils` overload are covered elsewhere. See
  feature-string-copy-intrinsic-norter. }
program test_string_copy_intrinsic;
var s, t: AnsiString;
begin
  s := 'Hello, World!';
  t := Copy(s, 1, 5);   writeln(t);   { Hello }
  t := Copy(s, 8, 5);   writeln(t);   { World }
  t := Copy(s, 8);      writeln(t);   { World!  (2-arg = rest) }
  t := Copy(s, 8, 999); writeln(t);   { World!  (count clamps to end) }
  t := Copy(s, 0, 3);   writeln(t);   { Hel     (index clamps to 1) }
  t := Copy(s, 99, 3);  writeln(Length(t):0);  { 0  (index past end) }
  s := Copy(s, 1, 5);   writeln(s);   { Hello   (assign over the source) }
end.

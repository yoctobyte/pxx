program test_write_fmt;
var i: Integer; s: String;
begin
  { Integer width: right-aligned }
  writeln(42:6);       { '    42' }
  writeln(-7:6);       { '    -7' }
  writeln(1000:4);     { '1000'  — no padding, value wider than field }
  writeln(0:3);        { '  0' }
  { String width }
  s := 'hi';
  writeln(s:6);        { '    hi' }
  writeln('ab':5);     { '   ab' }
  { No width — normal output }
  writeln(99);
  writeln('x');
end.

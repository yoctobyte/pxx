program test_str_val;
{ Str and Val, backed by the auto-included builtin unit. Str(x[:w], s) formats
  an integer (right-justified to width); Val(s, n, code) parses one (code = 0 on
  success, else 1-based position of the first offending character). }
var s: string; n: Int64; code: Integer;
begin
  Str(42, s);     writeln(s);                  { 42 }
  Str(-7, s);     writeln(s);                  { -7 }
  Str(0, s);      writeln(s);                  { 0 }
  Str(1234:6, s); writeln('[' + s + ']');      { [  1234] }

  Val('100', n, code);  writeln(n);  writeln(code);   { 100, 0 }
  Val('-25', n, code);  writeln(n);  writeln(code);   { -25, 0 }
  Val('9x', n, code);   writeln(code);                { 2: 'x' at pos 2 }
  Val('abc', n, code);  writeln(code);                { 1: no digits }
end.

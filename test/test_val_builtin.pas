{ The Val(s, dest, code) builtin. Regressions:
  - a 1-char source literal ('5') parses as a Char; the intrinsic must promote it
    to a string (else Length(s)/s[i] segfault).
  - a narrow `dest` (var Integer) must not be overrun by Val's Int64 write —
    marshalled through a hidden Int64 temp, then truncated.
  Closes bug-builtin-val-miscompiles. }
program test_val_builtin;

var
  v, code: Integer;
  i64: Int64;
  d: Double;

begin
  Val('5', v, code);     Writeln(v, ' ', code);   { 5 0    (1-char literal) }
  Val('55', v, code);    Writeln(v, ' ', code);   { 55 0 }
  Val('1a', v, code);    Writeln(v, ' ', code);   { 0 2    (error at pos 2) }
  Val('-42', v, code);   Writeln(v, ' ', code);   { -42 0 }
  Val('  88', v, code);  Writeln(v, ' ', code);   { 88 0   (leading spaces) }
  Val('x', v, code);     Writeln(v, ' ', code);   { 0 1    (error at pos 1) }
  Val('1000000000000', i64, code); Writeln(i64, ' ', code);  { 1000000000000 0 }
  Val('3', d, code);     Writeln(code);           { 0      (float dest) }
end.

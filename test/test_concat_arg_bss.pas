{$mode objfpc}
program test_concat_arg_bss;

{ Many AnsiString concat expressions passed directly as call arguments in the
  MAIN body. Each used to reserve an ~8 MB static buffer
  (bug-ansistring-concat-arg-static-bloat); the build asserts a small BSS (the
  Makefile checks the compiler's reported `bss=` is < ~1 MB). Each F returns the
  length of ESC + "[X" = 3, so 8 sites => 24. }

function F(const s: AnsiString): Integer;
begin
  F := Length(s);
end;

var t: Integer;
begin
  t := 0;
  t := t + F('' + #27 + '[A');
  t := t + F('' + #27 + '[B');
  t := t + F('' + #27 + '[C');
  t := t + F('' + #27 + '[D');
  t := t + F('' + #27 + '[E');
  t := t + F('' + #27 + '[F');
  t := t + F('' + #27 + '[G');
  t := t + F('' + #27 + '[H');
  writeln(t);              { 24 }
end.

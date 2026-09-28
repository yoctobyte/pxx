program test_stderr_separation;

{$mode objfpc}

{ Every write shape, once to StdErr and once to stdout, so that
  `prog 2>/dev/null` and `prog 1>/dev/null` each show exactly one stream.
  Checked against FPC 3.2.2 on both streams.

  Only x86-64 honoured the fd: i386, arm32, aarch64, riscv32 and xtensa sent
  every StdErr write to stdout, and x86-64 itself leaked the formatted float
  (`1.5:0:1`), whose runtime writer hard-coded fd 1.

  NO `Output` AND NO PChar VARIABLE, deliberately: either one pulls the
  Text-file unit, whose `StdErr` is a Text variable that shadows the constant,
  and every StdErr write below would then go through the Text RTL instead of
  the fd path this file exists to measure. }

var
  i: Integer;
  i64: Int64;
  b: Boolean;
  c: Char;
  d: Double;
  s: AnsiString;
  ss: ShortString;
begin
  i := -42; i64 := 1234567890123; b := True; c := 'Q'; d := 2.25;
  s := 'ansi'; ss := 'short';

  WriteLn(StdErr, 'E const');
  WriteLn('O const');
  WriteLn(StdErr, 'E int ', i, ' ', i:6, '|');
  WriteLn('O int ', i, ' ', i:6, '|');
  WriteLn(StdErr, 'E i64 ', i64);
  WriteLn('O i64 ', i64);
  WriteLn(StdErr, 'E bool ', b, ' ', b:7, '|');
  WriteLn('O bool ', b, ' ', b:7, '|');
  WriteLn(StdErr, 'E char ', c, c:3, '|');
  WriteLn('O char ', c, c:3, '|');
  WriteLn(StdErr, 'E float ', d:0:1, ' ', d:8:3, '|');
  WriteLn('O float ', d:0:1, ' ', d:8:3, '|');
  WriteLn(StdErr, 'E sci ', d);
  WriteLn('O sci ', d);
  WriteLn(StdErr, 'E str ', s, ' ', s:7, '|', ss, ' ', ss:8, '|');
  WriteLn('O str ', s, ' ', s:7, '|', ss, ' ', ss:8, '|');
  WriteLn(StdErr, 'E const width ', 'ab':5, '|');
  WriteLn('O const width ', 'ab':5, '|');
  Write(StdErr, 'E part1 ');
  Write(StdErr, 7);
  WriteLn(StdErr);
  Write('O part1 ');
  Write(7);
  WriteLn;
  WriteLn(StdErr);
  WriteLn('O bare');
  Write('O no newline, then ');
  WriteLn;
end.

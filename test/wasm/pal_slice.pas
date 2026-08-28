program PalSlice;

{ The WASI PAL backend, at the stage where the SEAM exists and nothing behind
  it is implemented.

  What this proves is not file I/O — nothing here writes a file. It is that a
  program which merely PULLS the PAL now compiles and runs. Before
  lib/rtl/platform/wasi existed, `uses SysUtils` did not compile for wasm32 at
  all: posix is the compiled-in default PAL, and wasm32 fell into it and died
  at parse time on `undefined variable (SYS_openat)`. Every SysUtils routine
  below was unreachable on this target for that reason and no other. }

uses SysUtils;

var
  s: string;
  i: Integer;
  ok: Boolean;

begin
  s := IntToStr(42) + '/' + UpperCase('ok') + '/' + LowerCase('LO');
  writeln(s);
  writeln('[', Trim('  padded  '), ']');
  writeln(Copy('abcdefgh', 3, 4), '|', Pos('def', 'abcdefgh'));
  writeln(StringOfChar('x', 5), '|', Length(StringOfChar('y', 3)));

  ok := TryStrToInt('123', i);
  writeln(ok, '|', i);
  ok := TryStrToInt('12x', i);
  writeln(ok);

  writeln(IntToHex(255, 4), '|', StrToIntDef('nope', -7));
  writeln(CompareText('ABC', 'abc'), '|', SameText('Q', 'q'));

  s := '';
  for i := 1 to 4 do s := s + IntToStr(i * i) + ',';
  writeln(s);
end.

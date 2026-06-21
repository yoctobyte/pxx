program lib_ansiterm;

uses ansiterm;

var
  s, expected: AnsiString;
  ESC: Char;
begin
  ESC := #27;

  s := AnsiColor(31, 'hello');
  expected := '' + ESC + '[31mhello' + ESC + '[0m';
  if s <> expected then
  begin
    writeln('AnsiColor failed');
    halt(1);
  end;

  s := AnsiRGB(255, 0, 128, 'world');
  expected := '' + ESC + '[38;2;255;0;128mworld' + ESC + '[0m';
  if s <> expected then
  begin
    writeln('AnsiRGB failed');
    halt(2);
  end;

  s := AnsiBgRGB(10, 20, 30);
  expected := '' + ESC + '[48;2;10;20;30m';
  if s <> expected then
  begin
    writeln('AnsiBgRGB failed');
    halt(3);
  end;

  s := AnsiReset;
  expected := '' + ESC + '[0m';
  if s <> expected then
  begin
    writeln('AnsiReset failed');
    halt(4);
  end;

  s := AnsiBold;
  expected := '' + ESC + '[1m';
  if s <> expected then
  begin
    writeln('AnsiBold failed');
    halt(5);
  end;

  s := AnsiClear;
  expected := '' + ESC + '[2J' + ESC + '[H';
  if s <> expected then
  begin
    writeln('AnsiClear failed');
    halt(6);
  end;

  s := AnsiMove(5, 10);
  expected := '' + ESC + '[5;10H';
  if s <> expected then
  begin
    writeln('AnsiMove failed');
    halt(7);
  end;

  { Verify raw mode compiles and runs safely without crashing (even if stdin is not a TTY) }
  AnsiSetRawMode(True);
  AnsiSetRawMode(False);

  { Verify ReadKey compiles and returns #0 when no input is available }
  if AnsiReadKey <> #0 then
  begin
    writeln('AnsiReadKey failed (expected #0 when stdin has no input)');
    halt(8);
  end;

  writeln('OK');
end.

program test_p_eof_of_input_shares_stdin_with_the_console_reader;
{ Bare read/readln/Eof read stdin through the console reader; Eof(Input),
  Eoln(Input) and Read(Input, ..) through textfile's Input. Both read fd 0, and
  each used to read past a byte the other held: `while not Eof(Input) do
  ReadLn(s)` lost the first byte and then looped for ever. Fed
  'xhello\n3 4\nab\n\ncd\nl1\nl2\n' on a pipe; every line matches fpc 3.2.2.
  bug-p-eof-of-input-on-a-pipe-loses-the-first-line-and-never-ends }
var s: string; c: Char; i, j, n: Integer;
begin
  Read(Input, c); Write('[', c, ']');
  ReadLn(s); Write('[', s, ']');
  Read(i); Read(Input, j); Write('[', i + j, ']');
  WriteLn('[', Eoln(Input), ']');
  ReadLn(Input);
  n := 0;
  while n < 7 do
  begin
    if Eoln(Input) then begin ReadLn; Write('<nl>'); end
    else begin Read(c); Write(c); end;
    Inc(n);
  end;
  WriteLn;
  n := 0;
  while not Eof(Input) do
  begin
    ReadLn(s); Inc(n); Write(n, ':', s, ' ');
    if n > 5 then begin WriteLn('RUNAWAY'); Halt(1); end;
  end;
  WriteLn('|', Eof(Input), Eof);
end.

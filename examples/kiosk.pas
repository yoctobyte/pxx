program kiosk;
{$MODE OBJFPC}{$H+}
uses sysutils;
var line: AnsiString; n, i: LongInt; s: Int64;
begin
  WriteLn;
  WriteLn('+--------------------------------------------+');
  WriteLn('|   pxx kiosk  --  busybox userland, qemu     |');
  WriteLn('|   compiler and app both built by pascal26   |');
  WriteLn('+--------------------------------------------+');
  WriteLn;
  WriteLn('commands:  sum N   primes N   about   sh   halt');
  while True do
  begin
    Write('kiosk> ');
    ReadLn(line);
    line := Trim(line);
    if line = 'about' then
      WriteLn('pxx self-hosting Pascal compiler, static, no libc.')
    else if line = 'halt' then
    begin
      WriteLn('bye'); Halt(0);
    end
    else if Copy(line, 1, 4) = 'sum ' then
    begin
      n := StrToIntDef(Trim(Copy(line, 5, 32)), 0);
      s := 0; for i := 1 to n do s := s + i;
      WriteLn('sum 1..', n, ' = ', s);
    end
    else if Copy(line, 1, 7) = 'primes ' then
    begin
      n := StrToIntDef(Trim(Copy(line, 8, 32)), 0);
      s := 0;
      for i := 2 to n do
      begin
        var d: LongInt; var p: Boolean;
        p := True; d := 2;
        while d * d <= i do begin if i mod d = 0 then begin p := False; Break; end; d := d + 1; end;
        if p then s := s + 1;
      end;
      WriteLn('primes below ', n, ' = ', s);
    end
    else if line <> '' then
      WriteLn('unknown: ', line);
  end;
end.

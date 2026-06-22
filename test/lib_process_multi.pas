program lib_process_multi;
{ Regression for the O_CLOEXEC pipe fix: two CONCURRENT children must each reach
  EOF + exit independently. Before the fix, the 2nd child inherited the 1st
  child's stdin write-end (pipes were not close-on-exec), so closing child A's
  stdin never delivered EOF to A and wait(A) deadlocked. Track B. }

uses sysutils, platform;

var
  inA, outA, inB, outB, pidA, pidB, ws, i: Integer;
  noargs: array of AnsiString;
  buf: array of Byte;
  n: Int64;
  sA, sB: AnsiString;
begin
  SetLength(noargs, 0);
  SetLength(buf, 64);

  inA := -1; outA := -1;
  pidA := ExecutePipeline('/bin/cat', noargs, inA, outA);
  inB := -1; outB := -1;
  pidB := ExecutePipeline('/bin/cat', noargs, inB, outB);

  if (pidA <= 0) or (pidB <= 0) then begin writeln('spawn failed'); halt(1); end;

  PalWrite(inA, PChar('A1'#10), 3);
  PalClose(inA);                 { must EOF child A even though B is still alive }
  for i := 0 to 63 do buf[i] := 0;
  n := PalRead(outA, @buf[0], 64);
  sA := '';
  for i := 0 to Integer(n) - 1 do if buf[i] <> 10 then sA := sA + Chr(buf[i]);
  ws := 0; PalWait4(pidA, @ws, 0, nil);

  PalWrite(inB, PChar('B2'#10), 3);
  PalClose(inB);
  for i := 0 to 63 do buf[i] := 0;
  n := PalRead(outB, @buf[0], 64);
  sB := '';
  for i := 0 to Integer(n) - 1 do if buf[i] <> 10 then sB := sB + Chr(buf[i]);
  ws := 0; PalWait4(pidB, @ws, 0, nil);

  PalClose(outA);
  PalClose(outB);

  writeln('A=', sA, ' B=', sB);
  if (sA = 'A1') and (sB = 'B2') then writeln('OK') else writeln('FAIL');
end.

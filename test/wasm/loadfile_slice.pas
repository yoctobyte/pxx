{ The `LoadFile` builtin (IR_CALL proc index -100) on wasm32.

  Every other target lowers this to builtinheap's PXXStrLoadFile; wasm calls
  PXXWasiLoadFile in compiler/builtin/wasibackend.pas, because PXXStrLoadFile
  is written over the four PXXSys* primitives, which have no wasm arm.

  The slice writes its own inputs first, so the two runs read identical bytes
  without a fixture file the harness has to install. }
program loadfile_slice;
var s, path: AnsiString; fd, i: Integer; buf: array[0..1023] of Byte;

procedure MakeFile(const nm: AnsiString; const body: AnsiString);
var f, k: Integer; p: AnsiString; b: array[0..1023] of Byte;
begin
  p := nm;
  f := sysopen(p, 577);            { O_WRONLY|O_CREAT|O_TRUNC }
  if f < 0 then begin WriteLn('make failed ', nm); Exit; end;
  for k := 1 to Length(body) do b[k - 1] := Byte(Ord(body[k]));
  if Length(body) > 0 then fd := Integer(syswrite(f, b, Length(body)));
  { the two-arg sysopen passes mode 0, so a file it CREATES is unreadable even
    to its own process -- the compiler's output path always pairs it with this }
  sysfchmod(f, 420);
  sysclose(f);
end;

begin
  MakeFile('lf_small.txt', 'hello, wasm');
  MakeFile('lf_empty.txt', '');

  { the ordinary case }
  s := 'PRESET';
  path := 'lf_small.txt';
  LoadFile(path, s);
  WriteLn('small_len=', Length(s));
  WriteLn('small=', s);

  { an EMPTY file must give an empty string, and must be distinguishable from
    a missing one only by the fact that both are empty -- what must NOT happen
    is a stale handle surviving, so `s` is preloaded each time }
  s := 'PRESET';
  path := 'lf_empty.txt';
  LoadFile(path, s);
  WriteLn('empty_len=', Length(s));

  { a missing file: length 0, and the OLD handle must have been released and
    replaced, not left in place }
  s := 'PRESET';
  path := 'lf_absent.txt';
  LoadFile(path, s);
  WriteLn('absent_len=', Length(s));

  { reload into the SAME destination twice: the second load must release the
    first load's handle. A leak is invisible here, but a double-free or a
    use-after-free shows as a wrong length or a trap. }
  path := 'lf_small.txt';
  LoadFile(path, s);
  LoadFile(path, s);
  LoadFile(path, s);
  WriteLn('reload_len=', Length(s));
  WriteLn('reload=', s);

  { a bigger file, to cross a single read and any staging-buffer boundary }
  s := '';
  for i := 1 to 300 do s := s + 'x';
  MakeFile('lf_big.txt', s);
  s := 'PRESET';
  path := 'lf_big.txt';
  LoadFile(path, s);
  WriteLn('big_len=', Length(s));
  if Length(s) > 0 then
    WriteLn('big_first=', s[1], ' big_last=', s[Length(s)])
  else
    WriteLn('big_first=<empty> big_last=<empty>');

  { the loaded string must be an ORDINARY managed string afterwards }
  path := 'lf_small.txt';
  LoadFile(path, s);
  s := s + '!';
  WriteLn('concat=', s);
  WriteLn('done');
end.

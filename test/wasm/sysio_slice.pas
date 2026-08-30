{ The sys* intrinsics on wasm32, against the native build.

  These are what compiler.pas itself bootstraps on: every output file it writes
  is sysopen / syswrite / sysfchmod / sysclose. On a native target the backend
  emits a raw syscall instruction; on wasm it calls compiler/builtin/
  wasibackend.pas, which resolves the path against WASI's preopen table. }
program sysi;
var fd: Integer; n: Int64; buf: array[0..127] of Byte; i: Integer;
    path: string;
begin
  path := 'intrin.txt';
  fd := sysopen(path, 577);            { O_WRONLY|O_CREAT|O_TRUNC }
  WriteLn('open_ok=', fd >= 0);
  for i := 0 to 11 do buf[i] := Byte(Ord('A') + i);
  n := syswrite(fd, buf, 12);
  WriteLn('wrote=', n);
  sysfchmod(fd, 420);
  sysclose(fd);
  WriteLn('closed');

  for i := 0 to 127 do buf[i] := 0;
  fd := sysopen(path, 0);              { O_RDONLY }
  WriteLn('reopen_ok=', fd >= 0);
  n := sysread(fd, buf, 127);
  WriteLn('read=', n);
  Write('data=');
  for i := 0 to Integer(n) - 1 do Write(Chr(buf[i]));
  WriteLn;
  sysclose(fd);

  { a path that does not exist must fail, and fail NEGATIVE -- a wrong errno
    sign is how "missing file" turns into a valid fd downstream }
  path := 'nosuchfile.txt';
  fd := sysopen(path, 0);
  WriteLn('missing_lt0=', fd < 0);
  WriteLn('done');
end.

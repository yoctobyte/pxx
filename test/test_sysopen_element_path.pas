program test_sysopen_element_path;
{ SysOpen given an ELEMENT or FIELD path: an array of ShortString, an array of
  AnsiString, a record field. Every backend took the path from the SYMBOL, so it
  read the array base: x86-64 segfaulted, riscv32 and xtensa answered False for
  a file that exists. The parser now copies such a path into a hidden AnsiString
  local first. /proc/self paths exist on every Linux host and under qemu-user.
  bug-a-an-indexed-shortstring-sysopen-path-segfaults-on-x86-64 }
type TR = record tag: Integer; path: ShortString; end;
var arr: array[0..1] of ShortString; aa: array[1..2] of AnsiString; r: TR;
    fd, i, ok: LongInt;
function Pos3(x: LongInt): Boolean; begin Pos3 := x > 2; end;
begin
  arr[0] := '/proc/self/stat'; arr[1] := '/nonexistent/pxx_no_such_file';
  aa[1] := '/proc/self/status'; aa[2] := '/proc/self/stat';
  r.tag := 1; r.path := '/proc/self/status';
  writeln('arr0 ', SysOpen(arr[0], 0) > 2);
  writeln('arr1 ', SysOpen(arr[1], 0) > 2);
  writeln('aa1  ', SysOpen(aa[1], 0) > 2);
  writeln('r    ', Pos3(SysOpen(r.path, 0)));
  ok := 0;
  for i := 1 to 2 do begin fd := SysOpen(aa[i], 0); if fd > 2 then begin Inc(ok); SysClose(fd); end; end;
  writeln('loop ', ok);
  writeln('arr0 again ', arr[0], ' ', aa[2]);
end.

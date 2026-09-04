program test_sysopen_shortstring_path;
{ SysOpen through a SHORTSTRING path -- the RAW branch of ir_codegen.inc's
  SysOpen arm, which is a different emitter from the one every existing test
  exercises.

  That arm branches on the path symbol's kind: a `tyAnsiString` path is a
  nul-terminated heap handle and is loaded directly, while anything else gets
  EmitTerminateString + EmitLeaStrDataRdi. test_cross_sysopen_family.pas
  declares `path: AnsiString` and is therefore entirely on the managed side, so
  when EmitTerminateString read the length at the wrong width the whole raw
  branch segfaulted with nothing red.

  NOT a cross test, deliberately, and the reason is a measurement rather than
  caution: on 2026-09-04 i386, aarch64 and arm32 REFUSE this shape by name
  (`target <arch>: SysOpen expects a managed AnsiString path`), while riscv32
  and xtensa compile it and answer FALSE for a file that exists -- silently
  wrong rather than refused. Filed as
  bug-a-riscv32-and-xtensa-accept-a-shortstring-sysopen-path-and-open-nothing.
  Wire the cross rows when that closes; three of them will be refusals until
  those targets grow the arm, which is a separate question.

  Both directions: a path that EXISTS and one that does not. The NUL terminator
  is written BEFORE open() is called, so it runs on both -- which is why the
  defect this guards crashed on a missing file too, and why that made it look
  like an open() bug rather than a length-width one. }
var
  sp: ShortString;
  fd, n: Integer;
  buf: array[0..7] of Char;
  mp: AnsiString;
begin
  { create the file through the MANAGED path, so this test's own setup does not
    depend on the branch it is testing. }
  mp := '/tmp/pxx_sysopen_shortstring_path.tmp';
  buf[0] := 'P'; buf[1] := 'X'; buf[2] := 'X'; buf[3] := '2'; buf[4] := '6';
  fd := SysOpen(mp, 577);          { O_WRONLY | O_CREAT | O_TRUNC }
  n := SysWrite(fd, buf, 5);
  SysFchmod(fd, 420);
  SysClose(fd);
  writeln('setup wrote ', n);

  sp := '/tmp/pxx_sysopen_shortstring_path.tmp';
  fd := SysOpen(sp, 0);
  writeln('short open  ', fd > 2);
  if fd > 2 then
  begin
    buf[0] := ' '; buf[1] := ' '; buf[2] := ' '; buf[3] := ' '; buf[4] := ' ';
    n := SysRead(fd, buf, 5);
    writeln('short read  ', n, ' ', buf[0], buf[1], buf[2], buf[3], buf[4]);
    SysClose(fd);
  end;

  sp := '/tmp/pxx_sysopen_shortstring_no_such_file_anywhere.tmp';
  writeln('short miss  ', SysOpen(sp, 0) < 0);
  writeln('SYSOPEN SHORTSTRING PATH OK');
end.

program test_asm_emit;

{ Exercises the EmitAsmX64 text assembler indirectly: every writeln(PChar) is
  emitted by EmitWriteCStr, which is itself written entirely in EmitAsmX64
  (mov/xor/cmp byte [reg]/inc/jmp/je with back+forward labels + syscall). Varied
  string lengths drive different strlen-loop iteration counts, so a mis-encoded
  jump or counter would corrupt the output. The TVarRec value union and Length()
  are checked alongside. Matches FPC 3.2.2 byte-for-byte. }

procedure show(const a: array of const);
var i: Integer;
begin
  for i := 0 to Length(a) - 1 do
  begin
    if a[i].VType = vtInteger then
      writeln('I=', a[i].VInteger)
    else if a[i].VType = vtAnsiString then
      writeln('S=', PChar(a[i].VAnsiString));
  end;
end;

begin
  { Varied lengths drive different strlen-loop trip counts in EmitWriteCStr. }
  show(['', 'ab', 'abc', 'a longer string here', 0, 123, -7]);
  writeln('---');
  show(['ww', 1, 'yy', 2, 'zzz', 3]);
end.

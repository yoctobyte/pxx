program test_cross_managed_strings;
{ Managed-string CONCAT, COMPARE and Copy, on every operand shape the xtensa
  marshalling arms distinguish: ansistring, frozen string, and Char.

  WHY THIS EXISTS AS A CROSS TEST, and specifically as an xtensa WINDOWED row:
  under the windowed ABI the string-helper marshalling quad was a4-a7, chosen
  because the Xtensa ABI says a2-a7 survive a call8 -- true of the ABI, false of
  this compiler, which keeps the WINDOWED FRAME POINTER in a7
  (EmitFrameAddrXtensa). So every concat and compare overwrote the frame pointer
  and the next frame-relative local read faulted, a long way from the cause and
  looking nothing like it.
  bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength

  PROVEN ABLE TO GO RED: under `--xtensa-abi=windowed` the pre-fix compiler
  dies on signal 7 (rc 135) on the Copy line alone; the fixed one prints the
  x86-64 oracle's output. The Call0 row is the control -- a7 is not the frame
  pointer there (a15 is), so Call0 codegen is byte-identical across the fix.

  EVERY OPERAND SHAPE, because the marshalling has a separate arm per shape and
  only one of them was measured when this was found: ansistring+ansistring,
  ansistring+Char, frozen+ansistring and ansistring+frozen each take a
  different pair of branches, and the Char arm is the one that emits the
  `movi a7, 1` that was seen holding 1 in the faulting register dump.

  A LOCAL IS READ AFTER EVERY HELPER CALL. That is the actual assertion: the
  helper's own result was never wrong, so a test that only checked the returned
  string would have passed on the broken compiler. What broke was everything
  the function did AFTERWARDS through its frame pointer. }
var
  s, t, r, u: AnsiString;
  f: string[8];
  i, guard: Integer;
begin
  s := 'abcdef';
  t := 'abcdef';
  f := 'zz';
  guard := 1234;

  writeln('len f      = ', Length(f));
  writeln('guard      = ', guard);
  writeln('copy 2,3   = ', Copy(s, 2, 3));
  writeln('guard      = ', guard);
  writeln('copy 1,4   = ', Copy(s, 1, 4));

  r := s + 'x';        writeln('s+char     = ', r, ' guard=', guard);
  r := s + t;          writeln('s+s        = ', r, ' guard=', guard);
  r := f + s;          writeln('frozen+s   = ', r, ' guard=', guard);
  r := s + f;          writeln('s+frozen   = ', r, ' guard=', guard);

  if s = t then writeln('s=t        = yes') else writeln('s=t        = no');
  writeln('guard      = ', guard);
  if s = 'zzz' then writeln('s=zzz      = yes') else writeln('s=zzz      = no');
  if s < 'abcdeg' then writeln('s<abcdeg   = yes') else writeln('s<abcdeg   = no');
  if f > s then writeln('f>s        = yes') else writeln('f>s        = no');
  writeln('guard      = ', guard);
  writeln('pos cd     = ', Pos('cd', s));

  { a loop, so the frame pointer must survive repeatedly rather than once }
  u := '';
  for i := 1 to 5 do
  begin
    r := Copy(s, i, 2);
    u := u + r;
  end;
  writeln('walk       = ', u, ' guard=', guard);
end.

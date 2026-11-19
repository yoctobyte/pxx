{ `Unaligned(p^)` at a misaligned address on a strict-alignment target.
  xtensa emitted a plain l32i/s32i and bus-errored; the deref is now marked and
  IRLowerAddress gives it a ragged address, so the load/store arms take their
  byte path (the one a packed record's misaligned field already used).
  Every misaligned access here goes through Unaligned -- a BARE misaligned
  `p^` faults on xtensa by design, as it would under any compiler there,
  which is why test_p_unaligned_is_a_transparent_lvalue (it compares against a
  bare deref) is not a row for these targets. Results are checked through the
  byte array, never through an aligned alias.
  bug-a-unaligned-dereference-bus-errors-on-xtensa }
program test_p_unaligned_takes_the_byte_path_on_strict_alignment_targets;
var
  buf: array[0..23] of Byte;
  i, fails: Integer;
  p: Pointer;
  d: LongWord;
  w: Word;
  q: Int64;

procedure Chk(const what: string; got, want: Int64);
begin
  if got = want then WriteLn(what, ' ok')
  else begin WriteLn(what, ' FAIL got ', got, ' want ', want); Inc(fails); end;
end;

begin
  fails := 0;
  for i := 0 to 23 do buf[i] := i;
  p := @buf[1];
  d := Unaligned(PLongWord(p)^);  Chk('read dword', d, $04030201);
  w := Unaligned(PWord(p)^);      Chk('read word', w, $0201);
  p := @buf[3];
  q := Unaligned(PInt64(p)^);     Chk('read qword', q, $0A09080706050403);

  p := @buf[1];
  Unaligned(PLongWord(p)^) := $11223344;
  Chk('write dword b0', buf[0], 0);
  Chk('write dword b1', buf[1], $44);
  Chk('write dword b4', buf[4], $11);
  Chk('write dword b5', buf[5], 5);
  p := @buf[7];
  Unaligned(PWord(p)^) := $A1B2;
  Chk('write word', buf[7] + 256 * buf[8], $A1B2);
  p := @buf[13];
  Unaligned(PInt64(p)^) := $0102030405060708;
  Chk('write qword lo', buf[13], 8);
  Chk('write qword hi', buf[20], 1);
  Chk('write qword after', buf[21], 21);
  p := @buf[1];
  Chk('read back dword', Unaligned(PLongWord(p)^), $11223344);
  WriteLn('fails=', fails);
end.

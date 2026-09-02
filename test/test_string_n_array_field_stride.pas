program test_string_n_array_field_stride;
{ An `array[0..N] of string[M]` RECORD FIELD must stride by the same slot a
  plain variable of that array type does.

  It strode by LOCAL_STR_CAP+8 = 264 instead of 18. A `string[N]` field is
  stored as tyString with its capacity in UFldStrCap -- deliberately, since the
  read/write codegen is identical and only the slot SIZE differs -- so the index
  path's `tk = tyString` arm claimed it and used the bare-string stride. The
  array-symbol and `p^[i]` base kinds both handle this; the record FIELD base
  was the third arm nobody wrote.

  WHY THE VALUE ROWS CANNOT CATCH IT, which is the whole reason this test is
  shaped like this. With the bug present, `r.inner[1] := 'bbbbbbbbbb'` followed
  by reading `r.inner[1]` returns 'bbbbbbbbbb' -- correctly, every time. The
  write and the read agree with each other because they use the SAME wrong
  stride. What actually happened is that both went 224 bytes past the END of a
  40-byte record and used memory belonging to something else. So the defect is
  invisible to any assertion on the value, and is only observable as a STRIDE
  or as damage to a neighbour. Both are asserted below.

  The stride row is asserted against a plain VAR of the same array type rather
  than against 18, so it states the invariant (a field strides like a variable)
  and stays correct if the frozen-string length word is ever narrowed to fpc's
  one byte.
  bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes }
type
  S10 = string[10];
  TA  = array[0..1] of S10;
  TR  = record inner: TA; tail: LongInt; end;
var
  r: TR;
  plain: TA;
  guard: array[0..63] of LongInt;
  i, bad, fieldStride, varStride: LongInt;
  p0, p1: ^Byte;
begin
  for i := 0 to 63 do guard[i] := 12345;
  r.tail := 777;

  p0 := @r.inner[0]; p1 := @r.inner[1];
  fieldStride := LongInt(p1) - LongInt(p0);
  p0 := @plain[0];   p1 := @plain[1];
  varStride := LongInt(p1) - LongInt(p0);

  { the invariant: a field strides like a variable of the same type }
  WriteLn('stride   ', Ord(fieldStride = varStride));

  { and the whole array must fit inside the record it is declared in }
  WriteLn('fits     ', Ord(fieldStride * 2 <= SizeOf(TR)));

  { the damage row -- the only one that saw this before the stride row existed }
  r.inner[0] := 'aaaaaaaaaa';
  r.inner[1] := 'bbbbbbbbbb';
  bad := 0;
  for i := 0 to 63 do if guard[i] <> 12345 then bad := bad + 1;
  WriteLn('guard    ', Ord(bad = 0));
  WriteLn('tail     ', Ord(r.tail = 777));

  { values, which passed throughout and are here to prove the fix kept them }
  WriteLn('values   ', Ord(r.inner[0] = 'aaaaaaaaaa'), Ord(r.inner[1] = 'bbbbbbbbbb'));
end.

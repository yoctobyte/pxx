program test_string_array_element_charwrite;
{ Regression: an indexed char write into a string that is itself an ARRAY
  ELEMENT — `a[i][1] := 'x'` on an `array[0..N] of string` — must copy-on-write
  through the element's handle, not scribble into the handle slot.

  riscv32's IR_INDEX handled only the SCALAR managed-string shape; the
  field/array-element shape (IR_FIELD / IR_INDEX with a 1-byte stride, which
  arm32 has always handled) fell through with no COW call and no deref, so a0
  held the element's SLOT ADDRESS and the character landed in the handle. The
  string's Length then read 0 and the handle was malformed — which in turn
  segfaulted the scope-exit element release, and is why that release had to be
  held back on riscv32.
  bug-a-riscv32-setlength-on-string-array-element-loses-length }
type TR = record s: string; end;
var a: array[0..2] of string; r: TR; s: string; i: Integer;
begin
  for i := 0 to 2 do begin SetLength(a[i], 4 + i); a[i][1] := 'x'; end;
  for i := 0 to 2 do writeln(Length(a[i]), a[i][1]);
  { the scalar shape, which always worked — must not regress }
  SetLength(s, 4); s[1] := 'y';
  writeln(Length(s), s[1]);
  { the record-FIELD shape, the other half of the same arm }
  SetLength(r.s, 6); r.s[1] := 'z';
  writeln(Length(r.s), r.s[1]);
  { read position must still deref, not COW }
  writeln(a[2][1], s[1], r.s[1]);
  writeln('OK');
end.

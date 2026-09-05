{ `New(p)` where the POINTEE is a named array type allocated the ELEMENT's size.

  `P1D = ^array[0..17] of Char` took TypeSlotSize(tyChar) = 1 byte, the
  allocator rounded that to 16, and every write past `p^[15]` landed in the
  next block. Silent, exit 0, and the corruption only shows up as some OTHER
  pointee's bytes changing -- which is how it was found: it was misfiled for a
  day as a defect in the char-array-row LOAD path, because a row that reads
  `103 104 32 0 0 0` is indistinguishable from a reader that stops early.

  The RECORD pointee was always right (RecSize answers for it), which is why
  nothing caught this: the shape everyone writes `New` for is the one arm that
  worked.

  THE SIZE ROWS ARE NOT THE ASSERTION -- allocator gaps are an implementation
  detail and this file does not claim fpc's. Rows 1-3 assert that the OBSERVABLE
  is right: `b^` still reads back what was written to it after `a^` was filled,
  for an array pointee, a 2-D array pointee and a record pointee. With the bug,
  filling `a^` overwrote the first two characters of `b^` and row 1 printed
  `qr################`.

  Row 4 is the FUNCTION spelling `q := New(P2D)`, which reads its size off the
  ALIAS row rather than off a variable's symbol -- a second carrier for one
  concept, and the source comment on that arm says the size rule changes in
  both arms or neither. It did not, so this row is what says it now does.

  Row 5 is the CONTROL: a pointer to a SCALAR takes the OTHER arm of the same
  conditional and must be untouched by this. It does not assert SizeOf(n^) --
  fpc's default mode makes Integer a smallint and answers 2 where pxx answers
  4, which is a mode question and not this ticket's, and asserting it here
  would make this file red for an unrelated reason.

  Every row is fpc 3.2.2's own output, byte for byte. }
program test_new_of_a_pointer_to_an_array_type;

type
  T1D = array[0..17] of Char;
  P1D = ^T1D;
  T2D = array[0..2, 0..5] of Char;
  P2D = ^T2D;
  TRc = record pad : array[0..17] of Char; end;
  PRc = ^TRc;
  PInt = ^Integer;

var
  a, b : P1D;
  c, d : P2D;
  e, f : PRc;
  q    : P2D;
  n    : PInt;
  i, j : Integer;
  s    : ShortString;

begin
  New(a); New(b);
  for i := 0 to 17 do b^[i] := '#';
  for i := 0 to 17 do a^[i] := Chr(Ord('a') + i);
  s := '';
  for i := 0 to 17 do s := s + b^[i];
  writeln('1-D pointee survives  : [', s, ']');
  Dispose(a); Dispose(b);

  New(c); New(d);
  for i := 0 to 2 do for j := 0 to 5 do d^[i][j] := '#';
  for i := 0 to 2 do for j := 0 to 5 do c^[i][j] := Chr(Ord('a') + i * 6 + j);
  s := '';
  for i := 0 to 2 do for j := 0 to 5 do s := s + d^[i][j];
  writeln('2-D pointee survives  : [', s, ']');
  Dispose(c); Dispose(d);

  New(e); New(f);
  for i := 0 to 17 do f^.pad[i] := '#';
  for i := 0 to 17 do e^.pad[i] := Chr(Ord('a') + i);
  s := '';
  for i := 0 to 17 do s := s + f^.pad[i];
  writeln('record pointee (was ok): [', s, ']');
  Dispose(e); Dispose(f);

  q := New(P2D);
  for i := 0 to 2 do for j := 0 to 5 do q^[i][j] := Chr(Ord('A') + i * 6 + j);
  s := '';
  for i := 0 to 2 do for j := 0 to 5 do s := s + q^[i][j];
  writeln('New as a function     : [', s, ']');
  Dispose(q);

  New(n);
  n^ := 1234;
  writeln('CONTROL scalar pointee: ', n^);
  Dispose(n);
end.

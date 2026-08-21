{ A typed const ARRAY must be stored as initialised data, not built by
  generated startup code.

  Measured before the fix (bug-a-a-typed-const-array-is-built-by-startup-code-
  not-stored-as-data): a 696-entry `array of UInt64` cost +20,152 bytes of CODE
  and 0 bytes of data -- about 29 bytes of machine code PER ELEMENT, executed at
  program start, in every binary that links the unit whether or not it ever
  reads the array. sysutils' Eisel-Lemire power-of-ten table alone carried ~40 KB
  of that. After: +0 code, +5,560 data (exactly the table's own bytes), +0 bss.

  This test is about VALUES, not sizes -- a size assertion would be brittle and
  a wrong byte is the failure that matters. Every element type that gets baked
  is here, because baking writes raw little-endian bytes and each width is its
  own chance to be wrong:

    * Single is the trap. A float literal is recorded as the DOUBLE's bit
      pattern whatever the declared type is, so copying the low 4 bytes gives
      garbage -- (0.0, -1.5, 2.5, 1e30) read back as (0, 0, 0, 3.06e-4) until
      the narrowing was added.
    * A non-zero and a NEGATIVE low bound (`array[-2..1]`) check that the
      element order in .data still matches what indexing computes.
    * The last three arrays must NOT be baked -- a string element is a heap
      handle, a record element a field list -- and must still work. Promotion
      is all-or-nothing per array and fails closed; these are the closed side.
    * WR is written to. Typed constants are writable in this dialect (FPC's
      writable-typed-constants mode), so the data must land in a WRITABLE
      section; a read-only placement would turn this line into a fault.

  Values verified identical to FPC 3.2.2, and identical again on i386, arm32,
  aarch64 and riscv32 -- the fixup that moves the symbol is decoded in the ELF
  writers, so every backend was affected at once. }
program test_const_array_in_data;
type
  TE = (eA, eB, eC);
  TR = record a, b: Integer; end;
const
  U:  array[0..3] of UInt64   = ($1122334455667788, 0, $FFFFFFFFFFFFFFFF, 7);
  I8: array[0..3] of Int64    = (-1, 9223372036854775807, -9223372036854775808, 0);
  C:  array[1..4] of Cardinal = ($DEADBEEF, 0, 1, $FFFFFFFF);
  W:  array[0..3] of Word     = (0, 65535, 258, 7);
  B:  array[0..3] of Byte     = (0, 255, 128, 1);
  SI: array[-2..1] of ShortInt= (-128, 127, 0, -1);
  D:  array[0..3] of Double   = (0.0, -1.5, 3.141592653589793, 1e300);
  S:  array[0..3] of Single   = (0.0, -1.5, 2.5, 1e30);
  L:  array[0..3] of LongInt  = (-2147483648, 2147483647, 0, -1);
  BO: array[0..3] of Boolean  = (True, False, True, True);
  CH: array[0..3] of Char     = ('a', 'Z', #0, '~');
  EN: array[0..2] of TE       = (eC, eA, eB);
  M2: array[0..1, 0..2] of Integer = ((1,2,3),(4,5,6));
  ST: array[0..2] of string   = ('one', 'two', 'three');
  RC: array[0..1] of TR       = ((a:1; b:2), (a:3; b:4));
var WR: array[0..2] of Integer = (10, 20, 30);
    i, j: Integer;
begin
  for i := 0 to 3 do write(U[i], ' ');   writeln;
  for i := 0 to 3 do write(I8[i], ' ');  writeln;
  for i := 1 to 4 do write(C[i], ' ');   writeln;
  for i := 0 to 3 do write(W[i], ' ');   writeln;
  for i := 0 to 3 do write(B[i], ' ');   writeln;
  for i := -2 to 1 do write(SI[i], ' '); writeln;
  { floats by comparison, not by rendering: the digits are Track F's business
    and this test is about the BYTES }
  write(D[0] = 0.0, ' ', D[1] = -1.5, ' ', D[2] > 3.14159, ' ', D[2] < 3.14160, ' ', D[3] > 1e299); writeln;
  write(S[0] = 0.0, ' ', S[1] = -1.5, ' ', S[2] = 2.5, ' ', S[3] > 9e29); writeln;
  for i := 0 to 3 do write(L[i], ' ');   writeln;
  for i := 0 to 3 do write(BO[i], ' ');  writeln;
  for i := 0 to 3 do write(Ord(CH[i]), ' '); writeln;
  for i := 0 to 2 do write(Ord(EN[i]), ' '); writeln;
  for i := 0 to 1 do for j := 0 to 2 do write(M2[i,j], ' '); writeln;
  for i := 0 to 2 do write(ST[i], ' ');  writeln;
  for i := 0 to 1 do write(RC[i].a, '/', RC[i].b, ' '); writeln;
  for i := 0 to 2 do write(WR[i], ' ');  writeln;
  WR[1] := 99;
  for i := 0 to 2 do write(WR[i], ' ');  writeln;
end.

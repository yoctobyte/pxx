program test_shortstring_byte_prefix;
{ The byte-length-prefix layout for `string[N]`, N <= 255 -- FPC's ShortString
  ABI. Compiled BOTH ways and both are asserted:

    default            tyFixedString, an 8-byte NativeInt length word
    -dPXX_SHORTSTRING  tyShortString, a single length byte

  THE FLAG IS PHASE-2 SCAFFOLDING AND IS OFF BY DEFAULT. Phase 4 of
  feature-p-implement-the-real-tyshortstring-byte-prefix-layout is what flips
  the default; this flag exists because phase 2 must write raw machine code for
  a kind no source spelling could produce, and code that cannot be run cannot be
  reviewed. It is the positive control the phase asked for.

  WHAT IS ASSERTED, and why it is not just SizeOf. A prefix-width bug is a
  wrong-OFFSET bug, so the rows are chosen to fail differently from each other:

    layout   the RAW BYTES -- the only row that sees the prefix directly. An
             implementation could get every other row right by being
             self-consistently wrong, and this one still fails.
    len      Length reads the prefix at its own width. Read an 8-byte prefix as
             1 byte and you truncate; read a 1-byte prefix as 8 and you get a
             length in the billions, which is the direction that segfaults.
    idx      s[1] is the first CHARACTER, at base+prefix. The index origin is
             `lo` in IR_INDEX and was spelled -7 for the 8-byte word.
    zero     s[0] is the classic shortstring LENGTH BYTE. It is base+0 under
             BOTH widths -- little-endian puts the low byte first -- so this row
             is expected to be identical in the two modes, and a difference here
             means an origin was moved that should not have been.
    write    WriteLn reads the count AND the data address off the prefix. Get
             one and not the other and it prints the right NUMBER of bytes from
             the wrong place, which is the silent shape.
    trunc    a source longer than the capacity truncates rather than running
             past the slot.
    guard    a neighbouring variable, to catch a write that overruns the slot.
             It is the row that a value-only test cannot replace: under a wrong
             prefix the chars can land outside an 11-byte slot while every read
             of the string itself still agrees with every write.

  THE EXPECTED OUTPUT IS THE SAME TEXT IN BOTH MODES except for the `sizeof`
  row, and that is the point rather than a coincidence: the layout is an
  implementation detail and every OBSERVABLE must be identical. `sizeof` is the
  one legitimate difference -- 18 against 11 -- and 11 is FPC's answer.
  Verified against FPC 3.2.2, which produces this file's output with `sizeof 11`. }
var
  s: string[10];
  guard: array[0..7] of LongInt;
  i, bad: Integer;
  b: ^Byte;
begin
  for i := 0 to 7 do guard[i] := 700 + i;

  s := 'hello';

  { the raw prefix+chars, the only row that sees the layout }
  b := Pointer(@s);
  Write('layout    ');
  for i := 0 to 5 do begin Write(b^, ' '); b := Pointer(PtrUInt(b) + 1); end;
  WriteLn;

  WriteLn('len       ', Length(s));
  WriteLn('idx       ', s[1], s[2], s[5]);
  WriteLn('zero      ', Ord(s[0]));
  WriteLn('write     <', s, '>');

  { truncation: 14 chars into a 10-char capacity }
  s := 'abcdefghijklmn';
  WriteLn('trunc     ', Length(s), ' <', s, '>');

  { and the slot's neighbour survived all of it }
  bad := 0;
  for i := 0 to 7 do
    if guard[i] <> 700 + i then bad := bad + 1;
  WriteLn('guard     ', bad);

  WriteLn('sizeof    ', SizeOf(s));
end.

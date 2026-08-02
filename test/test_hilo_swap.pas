program test_hilo_swap;
{ Hi/Lo/Swap split their argument by the size of ITS OWN type — nibbles for a
  byte, bytes for a 16-bit type, words for a 32-bit one, longwords for a 64-bit
  one (Swap has no nibble form: a 1-byte argument widens to 16 bits first).
  Every expected value below was measured from FPC, including the two that look
  like warts: ShortInt is sign-extended to 16 bits rather than split into
  nibbles, and a negative argument splits its two's complement.

  Before bug-pascal-hi-lo-always-split-a-32-bit-value-regardless-of-argument-type
  only the 32-bit rows were right: everything narrower widened into the Cardinal
  overload (hi(word($1234)) = 0) and an Int64 argument was TRUNCATED into it. }

var
  b: Byte; sb: ShortInt; w: Word; sw: SmallInt;
  l: LongInt; c: Cardinal; q: Int64; u: QWord;
begin
  b := $AB;                writeln(hi(b), ' ', lo(b), ' ', swap(b));
  b := 5;                  writeln(hi(b), ' ', lo(b), ' ', swap(b));
  sb := -86;               writeln(hi(sb), ' ', lo(sb), ' ', swap(sb));
  sb := 86;                writeln(hi(sb), ' ', lo(sb), ' ', swap(sb));
  w := $1234;              writeln(hi(w), ' ', lo(w), ' ', swap(w));
  sw := -4660;             writeln(hi(sw), ' ', lo(sw), ' ', swap(sw));
  l := $12345678;          writeln(hi(l), ' ', lo(l), ' ', swap(l));
  l := -305419896;         writeln(hi(l), ' ', lo(l), ' ', swap(l));
  c := $9ABCDEF0;          writeln(hi(c), ' ', lo(c), ' ', swap(c));
  q := $1122334455667788;  writeln(hi(q), ' ', lo(q), ' ', swap(q));
  q := -1;                 writeln(hi(q), ' ', lo(q), ' ', swap(q));
  u := $8899AABBCCDDEEFF;  writeln(hi(u), ' ', lo(u), ' ', swap(u));
  { A cast gives the expression a real type, so it dispatches like a variable. }
  writeln(hi(Byte(200)), ' ', lo(Byte(200)), ' ', swap(Byte(200)));
  writeln(hi(Word($1234)), ' ', lo(Word($1234)), ' ', swap(Word($1234)));
end.

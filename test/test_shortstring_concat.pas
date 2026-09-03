program test_shortstring_concat;
{ CONCAT over frozen strings, compiled in all FOUR string-build corners, and
  every row must print the same text in all four.

    PXX_MANAGED_STRING   chooses what bare `string` is
    PXX_SHORTSTRING      chooses what `string[N]` is

  WHY THIS TEST EXISTS. `s := s + 'cd'` on a plain `string[10]` SEGFAULTED on
  x86-64 under -dPXX_SHORTSTRING while every other target was correct
  (bug-a-string-concat-segfaults-on-x86-64-under-the-byte-prefix-mode). x86-64
  is the only backend that prepares the concat operands inline -- the others
  hand PXXStrConcat lengths their own frozen helpers computed, so they
  inherited the width fix and never had the defect. Concat is exercised
  constantly by the suite and NEVER under this flag, so the most common string
  operation in Pascal was simply not in the population.

  THE ROWS FAIL DIFFERENTLY, which is the point:

    self     s := s + lit -- the ticket's own six-line repro. Segfaulted.
    both     the managed arm with a frozen LHS and a frozen RHS.
    char     a Char operand, the arm a mis-tagged frozen operand fell INTO.
             It must keep working: the fix is a new branch in front of it.
    mixed    frozen + AnsiString and AnsiString + frozen. The second is the
             in-place append path (EmitAnsiStrAppendToSym), a SECOND copy of
             the same `= tyString` test, and it did not segfault -- it read
             eight bytes of [len][chars] as a length and died in the allocator
             with "out of memory (heap arena mmap failed)". A row that only
             checked for a crash would have called that arm fixed.
    constarg a concat in const-argument position, which is where the OOM was
             first seen rather than the SIGSEGV.
    loop     200 appends. A length read at the wrong width is a wild size to
             the allocator, and one iteration can be survivable where 200 are
             not.
    frozen   u := s + t stored into a THIRD variable. Under
             -uPXX_MANAGED_STRING this is the only row that reaches the INLINE
             frozen-concat arm (the 272-byte stack temp) rather than the
             managed one, and that arm read its operands at a hardcoded 8 too:
             it segfaulted in the -u/-d corner, the corner no default build
             visits. Every other row leaves that arm untouched.
    empty    a zero-length operand, because the copy loops branch on the
             length and 0 is the value a wrong-width read is least likely to
             produce.

  NO SINGLE-CHARACTER STRING LITERAL APPEARS ON THE RIGHT OF A `+` HERE, and
  that is deliberate: `u := s + 'q'` is folded to integer addition under
  -uPXX_MANAGED_STRING (it emits `lea rax,[s]; add rax,0x71` -- the address of
  s plus Ord('q')) and prints an empty string. That is a TYPING bug on the
  managed-vs-frozen axis, identical under the pinned compiler and identical in
  both byte-prefix modes, so it is not this test's subject; it has its own
  ticket. `ch` below is a Char VARIABLE, which is the working spelling. }
procedure Show(const q: string[12]);
{ const-argument position: the concat result is materialised into a parameter
  slot rather than into a variable of its own, which is where the OOM shape
  was first reported. }
begin
  WriteLn('constarg [', q, '] ', Length(q));
end;

var
  s, t, u: string[10];
  big: string[220];
  m: AnsiString;
  ch: Char;
  i: Integer;
begin
  s := 'ab'; t := 'XY'; ch := 'z';

  s := s + 'cd';          WriteLn('self     [', s, '] ', Length(s));
  s := 'ab'; s := s + t;  WriteLn('both     [', s, '] ', Length(s));
  s := 'ab'; s := s + ch; WriteLn('char     [', s, '] ', Length(s));
  s := 'ab'; s := ch + s; WriteLn('charl    [', s, '] ', Length(s));

  m := 'mm'; s := 'ab'; s := s + m;  WriteLn('mixed    [', s, '] ', Length(s));
  m := 'mm'; s := 'ab'; m := m + s;  WriteLn('append   [', m, '] ', Length(m));

  s := 'ab'; Show(s + 'QQ');

  big := '';
  for i := 1 to 200 do big := big + ch;
  WriteLn('loop     ', Length(big), ' ', big[1], big[200]);

  s := 'ab'; t := 'cd'; u := s + t;  WriteLn('frozen   [', u, '] ', Length(u));

  s := ''; s := s + t;    WriteLn('empty    [', s, '] ', Length(s));
  s := 'ab'; t := ''; s := s + t; WriteLn('emptyr   [', s, '] ', Length(s));
end.

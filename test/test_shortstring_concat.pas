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

    onechar  a ONE-CHARACTER string literal on the right, which lowers to an
             IR_CONST_INT and was therefore claimed by the -O1 imm-fold arm:
             `u := s + 'q'` emitted `lea rax,[s]; add rax,$71` -- the address
             plus Ord('q') -- and printed an empty string under
             -uPXX_MANAGED_STRING at -O1 and above, CORRECT at -O0. The arm
             excluded tyAnsiString results and there are two string result
             kinds. A Char variable and a two-character literal were both
             always fine, so only this one spelling was wrong; the `char` and
             `self` rows cannot see it.
             bug-a-a-one-char-string-literal-in-a-frozen-concat-folds-to-integer-addition

    field    a record FIELD as a concat operand, and `elemc` the array-element
             sibling. A field has NO SYMBOL to walk back to, so its own IR tag
             is the only record of its prefix width -- and the concat-operand
             normalisation in pasparser_expr.inc retags every frozen operand
             tyString, which is free for a variable (IRFrozenKindOfAddr asks
             the symbol) and lossy for a field. `u := s + r.f` SIGSEGVed under
             -dPXX_SHORTSTRING while `r.f` read, assigned and compared
             correctly in the same program. The array arm already defended
             itself; the field arm did not, and the array arm's own comment
             claimed it did.
             bug-a-a-frozen-record-field-as-a-concat-operand-segfaults

  THE `onechar` AND `loop1` ROWS ARE -O SENSITIVE and every other row is not,
  so run this at more than one level or the fold arm is untested: the whole
  defect lives at -O1..-O3 and disappears at -O0. }
procedure Show(const q: string[12]);
{ const-argument position: the concat result is materialised into a parameter
  slot rather than into a variable of its own, which is where the OOM shape
  was first reported. }
begin
  WriteLn('constarg [', q, '] ', Length(q));
end;

type
  R = record f: string[10]; end;
  TArr = array[0..2] of string[10];

var
  s, t, u: string[10];
  big: string[220];
  m: AnsiString;
  ch: Char;
  i: Integer;
  r: R;
  arr: TArr;
begin
  s := 'ab'; t := 'XY'; ch := 'z'; r.f := 'FLD'; arr[1] := 'ELM';

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

  s := 'ab'; u := s + 'q'; WriteLn('onechar  [', u, '] ', Length(u));
  u := ''; for i := 1 to 200 do u := u + 'x';
  WriteLn('loop1    ', Length(u), ' ', u[1], u[10]);

  s := 'ab'; u := s + r.f;   WriteLn('fieldr   [', u, '] ', Length(u));
  s := 'ab'; u := r.f + s;   WriteLn('fieldl   [', u, '] ', Length(u));
  m := r.f + ch;             WriteLn('fieldm   [', m, '] ', Length(m));
  i := 1; s := 'ab'; u := s + arr[i]; WriteLn('elemc    [', u, '] ', Length(u));

  s := ''; s := s + t;    WriteLn('empty    [', s, '] ', Length(s));
  s := 'ab'; t := ''; s := s + t; WriteLn('emptyr   [', s, '] ', Length(s));
end.

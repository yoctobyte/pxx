{ `High(WideChar)` answered "undefined variable (WideChar)" -- not a wrong
  bound, a REJECTED NAME, because OrdinalTypeBound returning False is read by
  TryFoldHighLowType as "not an ordinal type name at all" and falls through to
  the variable path. WideChar is in OrdinalNameToTk, so the name was recognised
  and then discarded one call later.

  The case in OrdinalTypeBound was COMPLETE when it was written: a WideChar
  variable was tyUInt16, which it lists, and 65535 is tyUInt16's right answer;
  a UCS4Char was a 32-bit integer kind. Giving each its own kind took it
  silently out of a case that still reads as correct. Same shape as the Variant
  unbox lists fixed in the same session -- carving a new kind out of an old one
  narrows every enumeration that named the old one, and none of them say so.

  1114111 is $10FFFF, the largest Unicode code POINT. It is what fpc 3.2.2
  answers, and it is NOT 4294967295 -- which is what deriving the bound from
  UCS4Char's 4-byte storage would have produced. Asserted here precisely
  because the plausible wrong answer differs from the right one; a row whose
  expected value equals what the machinery would produce by doing nothing
  cannot fail.

  Char and Word are the CONTROLS: they went through the same case and always
  worked, so a regression that breaks the whole function shows every column
  moving rather than the two new ones. .expected is fpc 3.2.2's own output. }
program test_high_low_of_the_carved_out_char_kinds;
{$mode delphi}
const
  { the CONST-fold path is a second site for the same concept (TryConstHighLowValue),
    and the two are documented as changing together -- so pin both, not one }
  WCHI = High(WideChar);
  U4HI = High(UCS4Char);
var
  n: LongInt;
begin
  WriteLn('high widechar    ', Ord(High(WideChar)));
  WriteLn('low  widechar    ', Ord(Low(WideChar)));
  WriteLn('high unicodechar ', Ord(High(UnicodeChar)));
  WriteLn('low  unicodechar ', Ord(Low(UnicodeChar)));
  WriteLn('high ucs4char    ', Ord(High(UCS4Char)));
  WriteLn('low  ucs4char    ', Ord(Low(UCS4Char)));

  { Ord() on both, and NOT because it reads better: WriteLn of a bare WideChar
    measures the OUTPUT ENCODING rather than the constant -- fpc renders it `?`
    on a non-Unicode console while pxx emits UTF-8, so the row would report a
    divergence that has nothing to do with High(). }
  WriteLn('const widechar   ', Ord(WCHI));
  WriteLn('const ucs4char   ', Ord(U4HI));

  { the controls }
  WriteLn('high char        ', Ord(High(Char)));
  WriteLn('low  char        ', Ord(Low(Char)));
  WriteLn('high word        ', High(Word));

  { usable as a bound, not merely printable }
  n := 0;
  if Ord(High(WideChar)) > Ord(High(Char)) then n := n + 1;
  if Ord(High(UCS4Char)) > Ord(High(WideChar)) then n := n + 1;
  WriteLn('ordered          ', n);

  WriteLn('CARVED CHAR BOUNDS OK');
end.

program test_length_of_a_pwidechar_counts_utf16_units;
{$mode delphi}{$H+}
{ Length(p) over a raw PWideChar answered a wild address-shaped number: the
  operand was never normalised, so it reached the runtime tkLength path, which
  reads a [data-8] length header off a pointer that has none.

  EVERY ROW HERE IS CHOSEN SO A NARROW strlen CANNOT PRODUCE IT, because the
  one-character "fix" for this defect is to add tyWideChar to IsNodePChar,
  which routes the operand into PCharToString. UTF-16 'abcd' is
  61 00 62 00 63 00 64 00, so that strlen stops at the first zero BYTE:

    row              correct   a narrow strlen would say
    ascii   'abcd'      4              1
    high    U+0100..    3              0   (the first BYTE of $0100 is 00)
    astral  surrogates  4              1

  A row expecting 4 that a narrow read also answers 4 would certify the bug.
  bug-p-length-of-any-pwidechar-reads-a-managed-length-header }
var
  ascii: array[0..4] of WideChar;
  high_: array[0..3] of WideChar;
  astral: array[0..4] of WideChar;
  empty: array[0..0] of WideChar;
  p: PWideChar;
  np: PWideChar;
  { the SAME TYPE spelled the other way. Both spellings must answer alike, and
    only one of them is a name the UTF-16 runtime's token scan can see: with
    `pwidechar` as the only trigger, this row did not merely answer wrong, it
    stopped COMPILING once Length started asking for a wide helper. A legal
    program refused on a spelling. }
  q: ^WideChar;
begin
  ascii[0] := 'a'; ascii[1] := 'b'; ascii[2] := 'c'; ascii[3] := 'd'; ascii[4] := #0;
  p := @ascii[0];
  Write('index :'); Write(' ', Ord(p[0])); Write(' ', Ord(p[1]));
  Write(' ', Ord(p[2])); Write(' ', Ord(p[3])); Write(' ', Ord(p[4])); WriteLn;
  WriteLn('ascii  ', Length(p));

  { every code unit has a ZERO LOW BYTE, so a narrow scan stops before unit 0 }
  high_[0] := WideChar($0100); high_[1] := WideChar($0200);
  high_[2] := WideChar($0300); high_[3] := #0;
  p := @high_[0];
  WriteLn('high   ', Length(p));

  { U+1F600 as a surrogate PAIR plus one ASCII unit: Length counts UNITS, so
    three code points are four units -- the same answer fpc gives. }
  astral[0] := WideChar($D83D); astral[1] := WideChar($DE00);
  astral[2] := 'x'; astral[3] := WideChar($00E9); astral[4] := #0;
  p := @astral[0];
  WriteLn('astral ', Length(p));

  empty[0] := #0;
  p := @empty[0];
  WriteLn('empty  ', Length(p));

  np := nil;
  WriteLn('nil    ', Length(np));

  q := @ascii[0];
  WriteLn('caret  ', Length(q));
end.

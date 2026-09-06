program test_indexing_a_string_cast_of_a_pointer_slot;
{ A STRING CAST OVER A POINTER SLOT, INDEXED -- the three spellings of one
  concept, in both positions.

  `type t = AnsiString; var r: Pointer; t(r)[2]` read a blank and
  `t(r)[2] := 'X'` stored nowhere, both without a diagnostic; the BUILT-IN
  spellings `AnsiString(r)[2]` and `String(r)[2]` did not parse at all
  (`expected ')' before '['`). Three observables, and three chances to find a
  story that fits -- so each was measured to its own boundary before anything
  was changed.

  The cause was one missing DISCRIMINATOR and not three defects: the IR's
  typed-pointer-cast index arm reads the alias index off the cast node, and a
  string cast carries -1, the built-in-cast marker -- which is also what the
  PChar ADAPTER carries. So a string cast was indexed by the adapter's rule:
  char element, byte stride, ZERO-based. `t(r)[1]` answered the second
  character. The tell is the tk on the cast node, not the alias index.

  .expected is fpc 3.2.2's own output, byte for byte.
  bug-p-indexing-a-string-cast-of-a-pointer-slot-reads-blank-and-stores-nowhere }
{$mode delphi}
type
  t = AnsiString;
  TSh = String[20];
var
  r: Pointer;
  s: AnsiString;
  sh: TSh;
  p: PChar;
begin
  t(r) := 'abcde';
  { A/B: the alias spelling, read then store. Both faces of the report. }
  WriteLn('A: ', t(r)[2]);
  t(r)[2] := 'X';
  WriteLn('B: ', t(r));
  { C/D: the built-in IDENTIFIER spelling of the same two. }
  WriteLn('C: ', AnsiString(r)[1]);
  AnsiString(r)[3] := 'Z';
  WriteLn('D: ', t(r));
  { E: the built-in KEYWORD spelling -- `String` lexes as its own token and
    never reaches the identifier path, which is why it needed its own arm. }
  WriteLn('E: ', String(r)[4]);
  { F/G: CONTROLS. A STRING operand through the same alias, where the cast is a
    value-level no-op and the subscript has always worked. F prints the cast and
    the plain spelling side by side; they must agree. }
  s := 'hello';
  WriteLn('F: ', t(s)[2], s[2]);
  t(s)[2] := 'Q';
  WriteLn('G: ', s);
  { H: CONTROL. A FROZEN-string alias, whose origin is the length prefix and not
    the handle -- a different lo, through the same arm. }
  sh := 'world';
  WriteLn('H: ', TSh(sh)[1]);
  { I: CONTROL, and the one that must NOT move: PChar indexing is 0-based, and
    the whole defect was a string cast being read by that rule. If this row ever
    starts answering the second character, the discriminator has been widened
    past the shape it was written for. }
  p := PChar(s);
  WriteLn('I: ', p[0], PChar(s)[1]);
  { J: CONTROL. The UNindexed alias cast in both its shapes -- a one-character
    literal operand (tagged tyChar, which a `not a string` test would sweep into
    the reinterpret and break) and Length over the pointer slot. }
  WriteLn('J: ', Pos(t(' '), 'a b'), ' ', Length(t(r)));
end.

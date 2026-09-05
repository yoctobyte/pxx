program test_ifopt_tracks_the_switch_it_names;
{ $IFOPT X+ asks whether switch X is on; $IFOPT X- asks whether it is off.
  Both used to answer False for every letter, so the wrong ARM compiled --
  silently, because a conditional has no diagnostic to get wrong.

  Every row sets the switch EXPLICITLY first. The default-state rows are
  deliberately absent: our $C (assertions) defaults on where fpc's defaults
  off, by a decision recorded at AssertionsVal in defs.inc, so a default row
  would either fail or pin fpc's answer instead of ours.

  $IFOPT R+ alone -- the form 113 of the 139 uses in fpc's own sources take --
  was already right before the fix, because fpc's R defaults off and "always
  False" agrees with "off". That is why every row here sets the switch and then
  asks BOTH signs: a row that only asks the sign matching the default cannot
  tell a tracking implementation from a hardwired one. }

procedure Say(const s: AnsiString);
begin
  WriteLn(s);
end;

begin
{$R+}
  {$IFOPT R+} Say('R on  : R+ yes'); {$ELSE} Say('R on  : R+ NO'); {$ENDIF}
  {$IFOPT R-} Say('R on  : R- yes'); {$ELSE} Say('R on  : R- no'); {$ENDIF}
{$R-}
  {$IFOPT R+} Say('R off : R+ yes'); {$ELSE} Say('R off : R+ no'); {$ENDIF}
  {$IFOPT R-} Say('R off : R- yes'); {$ELSE} Say('R off : R- NO'); {$ENDIF}
{$Q+}
  {$IFOPT Q+} Say('Q on  : Q+ yes'); {$ELSE} Say('Q on  : Q+ NO'); {$ENDIF}
{$Q-}
  {$IFOPT Q+} Say('Q off : Q+ yes'); {$ELSE} Say('Q off : Q+ no'); {$ENDIF}
{$I+}
  {$IFOPT I+} Say('I on  : I+ yes'); {$ELSE} Say('I on  : I+ NO'); {$ENDIF}
{$I-}
  {$IFOPT I-} Say('I off : I- yes'); {$ELSE} Say('I off : I- NO'); {$ENDIF}
{$C+}
  {$IFOPT C+} Say('C on  : C+ yes'); {$ELSE} Say('C on  : C+ NO'); {$ENDIF}
{$C-}
  {$IFOPT C+} Say('C off : C+ yes'); {$ELSE} Say('C off : C+ no'); {$ENDIF}
  { A letter neither compiler tracks: fpc's $IFOPT A+ stays false however
    {$A8} was set, because A is a NUMERIC switch. Reading it out of
    PackRecordsVal would have been plausible and wrong. }
{$A8}
  {$IFOPT A+} Say('A8    : A+ yes'); {$ELSE} Say('A8    : A+ no'); {$ENDIF}
  { Z is A's counter-example and the reason neither letter predicts the other:
    both are NUMERIC switches, A is dead and Z is LIVE. $IFOPT Z+ means "the
    enum minimum size is 4", so it is on by default and OFF once packing is
    asked for. Measured against fpc 3.2.2 across every spelling, 2026-09-05.
    Both signs on both settings, so a hardwired answer cannot pass. }
{$Z1}
  {$IFOPT Z+} Say('Z1    : Z+ yes'); {$ELSE} Say('Z1    : Z+ no'); {$ENDIF}
  {$IFOPT Z-} Say('Z1    : Z- yes'); {$ELSE} Say('Z1    : Z- NO'); {$ENDIF}
{$Z4}
  {$IFOPT Z+} Say('Z4    : Z+ yes'); {$ELSE} Say('Z4    : Z+ NO'); {$ENDIF}
  {$IFOPT Z-} Say('Z4    : Z- yes'); {$ELSE} Say('Z4    : Z- no'); {$ENDIF}
  { the long spelling reaches the same state }
{$PACKENUM 2}
  {$IFOPT Z+} Say('PE2   : Z+ yes'); {$ELSE} Say('PE2   : Z+ no'); {$ENDIF}
  { Lower case, which fpc accepts. }
{$R+}
  {$IFOPT r+} Say('lower : r+ yes'); {$ELSE} Say('lower : r+ NO'); {$ENDIF}
  { G, J and X: fpc defaults all three ON and so do we, so the PLUS rows are a
    real oracle comparison and belong here. Their MINUS rows do NOT -- fpc
    tracks the switch and pxx's behaviour is unconditional, so the answers
    diverge on purpose and pinning them here would either fail or quietly
    replace fpc's answer with ours. They live in
    test_ifopt_unconditional_letters.pas, next to the behavioural probe that
    justifies them. }
{$G+}
  {$IFOPT G+} Say('G+    : G+ yes'); {$ELSE} Say('G+    : G+ NO'); {$ENDIF}
{$J+}
  {$IFOPT J+} Say('J+    : J+ yes'); {$ELSE} Say('J+    : J+ NO'); {$ENDIF}
{$X+}
  {$IFOPT X+} Say('X+    : X+ yes'); {$ELSE} Say('X+    : X+ NO'); {$ENDIF}
end.

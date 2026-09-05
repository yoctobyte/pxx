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
  { Lower case, which fpc accepts. }
{$R+}
  {$IFOPT r+} Say('lower : r+ yes'); {$ELSE} Say('lower : r+ NO'); {$ENDIF}
end.

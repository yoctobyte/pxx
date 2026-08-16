{$mode objfpc}
program okcases;
type
  TDay   = (dMon, dTue, dWed, dThu);
  TDays  = set of TDay;
  TChars = set of Char;
  TBytes = set of Byte;
const
  CWeek : TDays = [dMon, dWed];
var
  ds: TDays; cs: TChars; bs: TBytes; d: TDay; c: Char; i: Integer;
procedure P(s: TDays); begin if dTue in s then WriteLn('p-yes') else WriteLn('p-no'); end;
procedure Q(s: TChars); begin if 'x' in s then WriteLn('q-yes') else WriteLn('q-no'); end;
procedure R(s: TBytes); begin if 7 in s then WriteLn('r-yes') else WriteLn('r-no'); end;
begin
  d := dTue; c := 'x'; i := 7;
  ds := [dMon, dTue];
  ds := ds + [dWed] - [dMon];
  ds := [d];
  ds := [dMon..dThu];
  ds := [];
  cs := ['a'..'z', '0'..'9', c];
  bs := [1, 2, 7, 200];
  P([dTue]); P([d]); P([dMon..dThu]); P([]); P(CWeek);
  Q(['x']); Q([c]); Q(['a'..'z']);
  R([7]); R([i]); R([0..255]);
  if d in [dMon, dTue] then WriteLn('in-yes');
  if c in ['a'..'z'] then WriteLn('c-yes');
  if i in [1, 7, 9] then WriteLn('i-yes');
  Include(ds, dWed); Exclude(ds, dWed);
  if dTue in CWeek then WriteLn('const-yes') else WriteLn('const-no');
end.

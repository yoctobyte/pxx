program test_pascal_system_qualified_intrinsic;

{ `System.X` names the BUILTIN on purpose — the same reason FPC code writes
  System.Move inside a class that has its own Move. A local spelled like the
  intrinsic must not take it away.

  Every variable below is deliberately named after the intrinsic used on the
  line under it, so each assertion fails if that one site loses its exemption.
  The last line then checks the variables still hold their own values, which is
  what catches the opposite error — an exemption written so broadly that the
  BARE name stops reaching the local.

  Ord/Chr and Length already had this and are not repeated here; High, Low,
  GetMem and the identifier-spelled ordinal casts (QWord) did not, and each was
  a live divergence: `var High: Integer` made `System.High(a)` report
  "undefined variable (High)".

  Expected output verified against FPC 3.2.2 (-Mdelphi) directly.
  meta-a-second-paths-reimplement-the-first-paths-decisions }

var
  a: array[0..4] of Integer;
  High, Low, GetMem, QWord: Integer;
  p: Pointer;
begin
  High := 99; Low := 98; GetMem := 97; QWord := 96;
  WriteLn(System.High(a));
  WriteLn(System.Low(a));
  p := System.GetMem(16);
  if p <> nil then WriteLn('alloc');
  FreeMem(p);
  WriteLn(System.QWord(300));
  WriteLn(High, ' ', Low, ' ', GetMem, ' ', QWord);
end.

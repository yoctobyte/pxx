{ The pxx side of test-packenum-gcc-oracle. Line 1 is {$PACKENUM 1}, line 2 is
  the same declarations with no directive -- the control that must DIFFER, since
  a directive that is accepted and discarded would still make line 1 match if
  our default happened to agree.

  TWide is the row a wrong implementation gets wrong: 300 does not fit in a
  byte, so it is TWO bytes under {$PACKENUM 1}. }
program packenum_pxx;

{$PACKENUM 1}
type
  TColP  = (cpRed, cpGreen, cpBlue);
  TWideP = (wpA, wpB = 300);
  TRecP  = record a: Byte; c: TColP; w: TWideP; b: Byte; end;

{$PACKENUM 4}
type
  TColU  = (cuRed, cuGreen, cuBlue);
  TWideU = (wuA, wuB = 300);
  TRecU  = record a: Byte; c: TColU; w: TWideU; b: Byte; end;

var p: TRecP; u: TRecU;
begin
  WriteLn(SizeOf(TColP), ' ', SizeOf(TWideP), ' ', SizeOf(TRecP), ' ',
          PtrUInt(@p.c) - PtrUInt(@p), ' ', PtrUInt(@p.w) - PtrUInt(@p), ' ',
          PtrUInt(@p.b) - PtrUInt(@p));
  WriteLn(SizeOf(TColU), ' ', SizeOf(TWideU), ' ', SizeOf(TRecU), ' ',
          PtrUInt(@u.c) - PtrUInt(@u), ' ', PtrUInt(@u.w) - PtrUInt(@u), ' ',
          PtrUInt(@u.b) - PtrUInt(@u));
end.

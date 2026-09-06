program test_a_nested_nd_subscript_does_not_clobber_the_outer_one;
{ NDInfoNDims / NDInfoLo[] / NDInfoSpan[] / NDIdxNode[] are GLOBAL parser
  scratch, and every N-D subscript loop holds them across a ParseExpr that can
  re-enter NodeArrNDInfo. A nested N-D subscript in any index position refilled
  them for the INNER array. THREE faces, and only the first one is loud:

    1  a refusal    `too many subscripts for array` -- the count check compared
                    this array's index count against the inner array's rank.
                    Position-dependent: rank >= 3, and a subscript that is
                    neither first (parsed before NodeArrNDInfo runs) nor last
                    (nothing reads the global after it). examples/chess/chess.pas
                    line 147 is exactly that shape.
    2  wrong ELEM   NDIdxNode[] overwritten -> the address names a different
                    element of the RIGHT array. z3[1,2,z2[1,1]] gave z3[1,1,2].
    3  wrong ROW    BuildPartialNDIndex computes `trailing` from NDInfoSpan[]
                    AFTER the loop, so a PARTIAL subscript got the inner array's
                    spans. This is the row that DISCRIMINATES: a fix that only
                    takes a local copy of the RANK passes faces 1 and 2 and
                    still fails this one.

  A nested subscript of rank 1 clobbers nothing -- NodeArrNDInfo refuses and
  clears -- so any probe built from a 1-D inner array measures this as CLEAN
  and is correct about a case the bug cannot reach. Every nested index here is
  itself N-D, deliberately.

  Values are asserted against fpc, which agrees on every row.
  bug-p-a-nested-n-d-subscript-clobbers-the-outer-subscripts-global-parse-state }
var
  z3: array[0..2, 0..2, 0..2] of Integer;
  z2: array[0..2, 0..2] of Integer;
  z4: array[0..1, 0..1, 0..1, 0..1] of Integer;
  i, j, k, l, fails: Integer;

procedure Chk(const what: AnsiString; got, want: Integer);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

{ face 3 needs a consumer that reads the whole ROW, so the trailing span
  actually reaches an address rather than being multiplied by one. }
procedure ChkRow(const what: AnsiString; const r: array of Integer; w0, w1, w2: Integer);
begin
  Chk(what + '[0]', r[0], w0);
  Chk(what + '[1]', r[1], w1);
  Chk(what + '[2]', r[2], w2);
end;

begin
  fails := 0;
  for i := 0 to 2 do
    for j := 0 to 2 do
    begin
      z2[i,j] := i + j;                     { z2[1,1] = 2, in range for z3 }
      for k := 0 to 2 do z3[i,j,k] := i * 100 + j * 10 + k;
    end;
  for i := 0 to 1 do for j := 0 to 1 do for k := 0 to 1 do for l := 0 to 1 do
    z4[i,j,k,l] := i * 1000 + j * 100 + k * 10 + l;

  { face 1 -- the refusal. Every position of a rank-3 and a rank-4 array, with
    an N-D nested index. Reaching this line at all is half the assertion. }
  Chk('pos1/3',  z3[z2[1,1], 1, 0],       210);
  Chk('pos2/3',  z3[1, z2[1,1], 0],       120);
  Chk('pos3/3',  z3[1, 2, z2[1,1]],       122);
  Chk('pos2/4',  z4[1, z2[0,1], 1, 0],    1110);
  Chk('pos3/4',  z4[1, 1, z2[0,1], 0],    1110);
  Chk('bracket', z3[1][z2[1,1]][0],       120);

  { face 2 -- the wrong element. z2[0,2] and z2[2,0] carry the SAME VALUE 2 as
    z2[1,1] but different index nodes, so a result that tracks the inner
    INDICES rather than the inner VALUE is caught here and nowhere else.
    Pre-fix these gave 112 / 22 / 202 for one expected answer. }
  Chk('samevalA', z3[1, 2, z2[1,1]], 122);
  Chk('samevalB', z3[1, 2, z2[0,2]], 122);
  Chk('samevalC', z3[1, 2, z2[2,0]], 122);

  { face 3 -- the wrong row. PARTIAL subscript: two of three, so `trailing` is
    3 and not 1. Pre-fix, row 2 read `12 20 21` -- flat 5 instead of flat 15,
    i.e. trailing computed as 1 from the inner array's rank. }
  ChkRow('rowctl', z3[1, 2],          120, 121, 122);
  ChkRow('rownest', z3[1, z2[1,1]],   120, 121, 122);
  ChkRow('rownest0', z3[z2[1,1], 2],  220, 221, 222);

  { the no-nesting controls: these were never broken, and a fixture whose rows
    all pass for a reason unrelated to the bug is not a fixture. }
  Chk('ctl3', z3[1, 2, 2],       122);
  Chk('ctl4', z4[1, 1, 1, 0],    1110);

  WriteLn('fails=', fails);
  WriteLn('NDNESTED OK');
end.

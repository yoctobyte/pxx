program test_nd_subarray_as_param;
{ A ROW of a fixed N-D array, handed to a parameter in every mode.

  bug-a-2d-array-row-as-a-const-array-param-still-segfaults

  `SumC(pa[0])` on `pa: array[0..2] of TG` SEGFAULTED on all five targets, in
  `const`, by-value and open-array modes, while `var` and `out` on the same row
  were fine. The split is the diagnosis: `var`/`out` must pass an address and so
  took IRLowerAddress, which was right all along; every mode that is free to
  form a COPY resolved its source through a helper that knew only whole
  identifiers and record fields. A row fell past it to the scalar tail, where
  the argument became an IR_LOAD_MEM of the row's first 8 bytes -- so the callee
  received element [0][0]'s VALUE where the row's address belonged. NULL for a
  zeroed array; a plausible wrong pointer for a populated one.

  The 3-D rows are the second half of the same operation. `pb[1][2]` was
  rejected outright -- `wrong number of array subscripts` -- which is untrue,
  and untrue in a way that HID the 2-D defect from any test written in one
  file: the compile error stops the run before the miscompiled row executes.
  One builder now answers for every k, so the row and the plane cannot diverge.

  Every cell of both tables on the ticket is here, INCLUDING the two controls
  that must stay green: `q[0].a` (a record field inside an array element -- an
  array subscript in the access path, but the final step is a field) and `r.a`
  by value. A fix that repaired the row by sending every aggregate member down
  the slow path would pass a test that watched only the failing cells. }
type TG   = array[0..3] of Int64;
     TPa  = array[0..2] of TG;
     TPa2 = array[0..2, 0..3] of Int64;
     TPb  = array[0..1] of TPa;
     TRec = record a, b: TG; end;
     TQ   = array[0..1] of TRec;
     TR2  = record rows: TPa; end;

function SumC(const g: TG): Int64;
var i: Integer; begin SumC := 0; for i := 0 to 3 do SumC := SumC + g[i]; end;
function SumV(g: TG): Int64;
var i: Integer; begin SumV := 0; for i := 0 to 3 do SumV := SumV + g[i]; end;
function SumO(const g: array of Int64): Int64;
var i: Integer; begin SumO := 0; for i := 0 to High(g) do SumO := SumO + g[i]; end;
function SumVarOA(var g: array of Int64): Int64;
var i: Integer; begin SumVarOA := 0; for i := 0 to High(g) do SumVarOA := SumVarOA + g[i]; end;
procedure BumpVar(var g: TG);
var i: Integer; begin for i := 0 to 3 do g[i] := g[i] + 100; end;
procedure FillOut(out g: TG);
var i: Integer; begin for i := 0 to 3 do g[i] := 7; end;

var pa: TPa; pa2: TPa2; pb: TPb; r: TRec; q: TQ; r2: TR2; std: TG;
    i, j, k: Integer; fails: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin
    WriteLn('WRONG ', what, ' = ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;
  for i := 0 to 3 do
  begin
    std[i] := 1; r.a[i] := 3; r.b[i] := 0;
    q[0].a[i] := 5; q[1].a[i] := 0;
  end;
  for i := 0 to 2 do for j := 0 to 3 do
  begin
    pa[i][j] := 2 + i; pa2[i, j] := 20 + i; r2.rows[i][j] := 30 + i;
  end;
  for i := 0 to 1 do for j := 0 to 2 do for k := 0 to 3 do pb[i][j][k] := 40 + i * 10 + j;

  { the controls first, so a run that dies part-way says WHERE }
  Chk('standalone const', SumC(std),   4);
  Chk('standalone value', SumV(std),   4);
  Chk('field const',      SumC(r.a),   12);
  Chk('field value',      SumV(r.a),   12);
  Chk('rec-in-array const', SumC(q[0].a), 20);
  Chk('rec-in-array value', SumV(q[0].a), 20);

  { table 1 -- every parameter mode over a 2-D row }
  Chk('row const',         SumC(pa[0]), 8);
  Chk('row byvalue',       SumV(pa[0]), 8);
  Chk('row const openarr', SumO(pa[0]), 8);
  Chk('row var openarr',   SumVarOA(pa[0]), 8);
  BumpVar(pa[1]);
  Chk('row var writes',    SumC(pa[1]), 3 * 4 + 400);
  FillOut(pa[2]);
  Chk('row out writes',    SumC(pa[2]), 28);

  { table 2 -- the remaining containers }
  BumpVar(std);
  Chk('standalone var',   SumC(std),   404);
  BumpVar(r.b);
  Chk('field var',        SumC(r.b),   400);
  Chk('row via record const', SumC(r2.rows[0]), 120);
  Chk('row via record value', SumV(r2.rows[0]), 120);
  Chk('comma-2d row const',   SumC(pa2[1]), 84);

  { 3-D: a PLANE is a row one level up, and forming a reference to one used to
    be a compile error rather than a wrong value }
  Chk('3d plane const',    SumC(pb[1][2]), 4 * 52);
  Chk('3d plane comma',    SumC(pb[1, 2]), 4 * 52);
  Chk('3d addr full',      Int64(PtrUInt(@pb[0][0][1]) - PtrUInt(@pb[0][0][0])), 8);
  Chk('3d addr one level', Int64(PtrUInt(@pb[1])       - PtrUInt(@pb[0])),       96);
  Chk('3d addr two level', Int64(PtrUInt(@pb[0][1])    - PtrUInt(@pb[0][0])),    32);

  if fails <> 0 then begin WriteLn('FAILURES: ', fails); Halt(1); end;
  WriteLn('ND SUBARRAY OK');
end.

program test_managed_temp_branch_lifetime;
{ Lifetime of a by-value managed-record TEMP created inside a branch.

  d27b4a28a moved the finalize of such a temp out of the merge block and into
  the arm that created it, and made the epilogue skip an all-zero record's heap
  lock. Both are lifetime changes, and the failure modes are silent: finalizing
  twice is a double release, finalizing never is a leak, and skipping a record
  that DOES own something is a leak that looks like a speedup.

  Every case below is checked by a value the program prints, not by timing. }
type
  TRec = record
    tag:   Integer;
    items: array of Int64;
  end;

var
  i, taken, skipped: Integer;
  sink: Int64;

function Make(v: Int64): TRec;
begin
  SetLength(Result.items, 3);
  Result.items[0] := v;
  Result.items[1] := v * 2;
  Result.items[2] := v * 3;
  Result.tag := 1;
end;

function Sum(r: TRec): Int64;    { BY VALUE — the caller mints a temp for this }
begin
  Sum := r.items[0] + r.items[1] + r.items[2];
end;

{ The shape the fix is about: the managed type is named ONLY inside a branch
  that this loop never takes. }
function NeverTaken(x: Int64): Int64;
begin
  if x < 0 then NeverTaken := Sum(Make(x)) else NeverTaken := x;
end;

{ The same shape with the branch TAKEN, so the temp really is created and must
  be finalized exactly once. }
function AlwaysTaken(x: Int64): Int64;
begin
  if x >= 0 then AlwaysTaken := Sum(Make(x)) else AlwaysTaken := 0;
end;

{ A path that leaves the arm WITHOUT reaching the sunk flush. The epilogue is
  the backstop; if it were not, this leaks. }
function ExitsFromArm(x: Int64): Int64;
begin
  if x >= 0 then
  begin
    ExitsFromArm := Sum(Make(x));
    Exit;
  end;
  ExitsFromArm := 0;
end;

{ Both arms mint a temp: whichever runs must finalize its own and not the
  other's. }
function BothArms(x: Int64): Int64;
begin
  if (x mod 2) = 0 then BothArms := Sum(Make(x)) else BothArms := Sum(Make(x + 1));
end;

begin
  taken := 0; skipped := 0; sink := 0;
  for i := 1 to 50000 do
  begin
    sink := sink + NeverTaken(i);
    sink := sink + AlwaysTaken(i);
    sink := sink + ExitsFromArm(i);
    sink := sink + BothArms(i);
    if NeverTaken(-1) = -6 then Inc(taken) else Inc(skipped);
  end;
  writeln('sink ', sink);
  writeln('taken ', taken);
  writeln('skipped ', skipped);
end.

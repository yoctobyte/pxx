program test_a_pointer_to_a_fixed_array_is_a_copying_open_array_argument;
{ bug-p-a-pointer-to-a-fixed-array-segfaults-as-a-copying-open-array-argument

  `Take(p^)` where `p: ^array[3..7] of LongInt` and Take takes
  `const array of LongInt` SEGFAULTED. StaticArraySourceInfo -- the one
  resolver both the by-value/const arm and the var/out arm ask "what static
  array is behind this argument" -- knew four shapes (a plain identifier, a
  record field, a partial N-D row, a slice) and not the deref. `p^` fell past
  all four to the scalar tail and the callee received the POINTER'S OWN BYTES
  where the array's address belonged.

  THE NEIGHBOUR THAT WORKED IS WHY NOBODY HIT IT. `p2^[1]` -- a ROW of a 2-D
  pointee -- was already right, because a subscript reaches the AN_INDEX arm.
  So the deref spelling worked for a subscript OF the pointee and not for the
  pointee ITSELF, and every probe anyone had written for pointer-to-array
  arguments used the subscripted form.

  IT IS ALSO WHY THE ARM IS NOT A FIFTH PRIVATE SWITCH. The arm asks
  DerefPtrArrayShape, which resolves the two deref spellings (the pointer
  SYMBOL and the pointee's ArrType row) once for everybody. That reader had to
  be widened to rank 1 before this fix was possible -- it answered only for
  rank >= 2 -- and this arm is its first caller.
  refactor-p-nodearrndinfo-answers-nothing-for-a-rank-1-array

  Every row is byte-identical to fpc 3.2.2. }

type
  TPt = record
    x, y: LongInt;
  end;
  TA1 = array[3..7] of LongInt;     { rank 1, NON-ZERO low bound }
  PA1 = ^TA1;
  TAR = array[0..2] of TPt;         { a RECORD element -- the stride matters }
  PAR = ^TAR;
  TA2 = array[0..1, 0..2] of LongInt;
  PA2 = ^TA2;

var
  fails: Integer;
  a1: TA1;  p1: PA1;
  ar: TAR;  pr: PAR;
  a2: TA2;  p2: PA2;
  i, j: LongInt;

procedure CheckInts(const x: array of LongInt; const what: AnsiString;
                    wantLen, w0, wLast: LongInt);
begin
  if Length(x) <> wantLen then
  begin
    WriteLn('FAIL ', what, ': length ', Length(x), ' want ', wantLen);
    fails := fails + 1;
    Exit;
  end;
  if (x[0] <> w0) or (x[High(x)] <> wLast) then
  begin
    WriteLn('FAIL ', what, ': ends ', x[0], '..', x[High(x)],
            ' want ', w0, '..', wLast);
    fails := fails + 1;
  end;
end;

{ BY VALUE, not const -- a different arm of the same resolver, and the one
  that must COPY rather than merely point. }
procedure ByValue(x: array of LongInt; const what: AnsiString;
                  wantLen, w0, wLast: LongInt);
begin
  if (Length(x) <> wantLen) or (x[0] <> w0) or (x[High(x)] <> wLast) then
  begin
    WriteLn('FAIL ', what, ': got [', Length(x), '] ', x[0], '..', x[High(x)]);
    fails := fails + 1;
  end;
end;

{ VAR -- the copy-OUT registration. A row that only read would pass with the
  write-back broken, so this one MUTATES and the caller checks the original. }
procedure BumpAll(var x: array of LongInt);
var k: LongInt;
begin
  for k := 0 to High(x) do x[k] := x[k] + 1;
end;

procedure CheckPts(const x: array of TPt; const what: AnsiString;
                   wantLen, w0x, wLastX: LongInt);
begin
  if Length(x) <> wantLen then
  begin
    WriteLn('FAIL ', what, ': length ', Length(x), ' want ', wantLen);
    fails := fails + 1;
    Exit;
  end;
  if (x[0].x <> w0x) or (x[High(x)].x <> wLastX) then
  begin
    WriteLn('FAIL ', what, ': ends ', x[0].x, '..', x[High(x)].x,
            ' want ', w0x, '..', wLastX);
    fails := fails + 1;
  end;
  if x[High(x)].y <> wLastX + 100 then
  begin
    WriteLn('FAIL ', what, ': the second field did not ride along');
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  for i := 3 to 7 do a1[i] := i * 2;
  for i := 0 to 2 do begin ar[i].x := i; ar[i].y := 100 + i; end;
  for i := 0 to 1 do for j := 0 to 2 do a2[i, j] := i * 10 + j;
  p1 := @a1; pr := @ar; p2 := @a2;

  { 1: THE CONTROL. The plain variable was always right; it is the arm the
    deref one is modelled on, and a fix that broke it would look like a fix
    that worked. }
  CheckInts(a1, '1: a plain variable (control)', 5, 6, 14);

  { 2: THE ROW THIS FILE EXISTS FOR. Before the fix this segfaulted -- not a
    wrong value, a dead process, which is why the file asserts the LENGTH
    first: a scalar tail delivers a length nobody can predict. }
  CheckInts(p1^, '2: a whole rank-1 pointee, const', 5, 6, 14);

  { 3: by value -- the copying arm proper. }
  ByValue(p1^, '3: a whole rank-1 pointee, by value', 5, 6, 14);

  { 4: var, and the assertion is on the ORIGINAL. A read-only row would pass
    with the copy-back broken. }
  BumpAll(p1^);
  if (a1[3] <> 7) or (a1[7] <> 15) then
  begin
    WriteLn('FAIL 4: var did not write back: ', a1[3], '..', a1[7]);
    fails := fails + 1;
  end;
  a1[3] := 6; a1[7] := 14;
  for i := 4 to 6 do a1[i] := i * 2;

  { 5: a RECORD element. The element SIZE drives the stride and a record is
    where getting it wrong is visible rather than wrong by luck. }
  CheckPts(pr^, '5: a record-element pointee', 3, 0, 2);

  { 6: THE NEIGHBOUR THAT ALREADY WORKED, kept as the boundary. A ROW of a 2-D
    pointee reaches the AN_INDEX arm, not the new one -- which is exactly why
    this defect survived: every existing probe for pointer-to-array arguments
    used this spelling. }
  CheckInts(p2^[1], '6: a row of a 2-D pointee (the working neighbour)', 3, 10, 12);

  { 7: the NON-ZERO low bound is not decoration. An open array is always
    0..High(x) inside the callee, so a resolver that carried the low bound
    into the count would answer 8 here instead of 5. }
  CheckInts(p1^, '7: the low bound does not leak into the count', 5, 6, 14);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('PTRARRARG OK');
end.

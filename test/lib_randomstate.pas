program lib_randomstate;
{ Per-stream PRNG state (feature-random-library slice 7).

  The point of TRandomState is that a threaded caller gets an independently
  REPRODUCIBLE stream with no lock. Both halves of that matter and both are
  asserted here: same seed replays exactly, split children never collide, and a
  split is itself reproducible from the parent seed.

  Single-threaded and bounded, so it is safe for the lib-test gate; the
  under-threads behaviour of the SHARED generator is exercised separately. }
uses random;
var fails: Integer;
procedure Chk(const n: AnsiString; ok: Boolean);
begin if ok then writeln('ok   ', n) else begin writeln('FAIL ', n); fails := fails + 1; end; end;

var
  a, b, c: TRandomState;
  parent: TRandomState;
  kids: array[0..7] of TRandomState;
  v1, v2: array[0..99] of UInt64;
  i, j, dup: Integer;
  hits: array[0..7] of Int64;
  tot: Int64;
begin
  fails := 0;

  { reproducible: same seed -> same stream }
  RandomStateSeed(a, 12345); RandomStateSeed(b, 12345);
  for i := 0 to 99 do begin v1[i] := RandomStateNext(a); v2[i] := RandomStateNext(b); end;
  dup := 0;
  for i := 0 to 99 do if v1[i] <> v2[i] then dup := dup + 1;
  Chk('same seed reproduces the stream', dup = 0);

  { different seed -> different stream }
  RandomStateSeed(c, 12346);
  dup := 0;
  for i := 0 to 99 do if RandomStateNext(c) = v1[i] then dup := dup + 1;
  Chk('different seed diverges', dup < 3);

  { split gives independent, non-overlapping streams }
  RandomStateSeed(parent, 999);
  for i := 0 to 7 do RandomStateSplit(parent, kids[i]);
  dup := 0;
  for i := 0 to 7 do
    for j := 0 to 7 do
      if i <> j then
        if RandomStateNext(kids[i]) = RandomStateNext(kids[j]) then dup := dup + 1;
  Chk('split streams are distinct', dup = 0);

  { split is itself reproducible: same parent seed -> same child stream.
    Derived fresh on both sides; kids[] above has already been advanced. }
  RandomStateSeed(parent, 999);
  RandomStateSplit(parent, a);
  RandomStateSeed(c, 999);
  RandomStateSplit(c, b);
  Chk('split is reproducible', RandomStateNext(a) = RandomStateNext(b));

  { range stays in bounds and covers }
  RandomStateSeed(a, 42);
  for i := 0 to 7 do hits[i] := 0;
  for i := 1 to 80000 do
  begin
    j := RandomStateRange(a, 0, 7);
    if (j < 0) or (j > 7) then begin Chk('range out of bounds', False); Break; end;
    hits[j] := hits[j] + 1;
  end;
  tot := 0;
  for i := 0 to 7 do tot := tot + hits[i];
  Chk('range total', tot = 80000);
  dup := 0;
  for i := 0 to 7 do if (hits[i] < 8000) or (hits[i] > 12000) then dup := dup + 1;
  Chk('range roughly uniform', dup = 0);

  { zero seed must not produce the all-zero fixed point }
  RandomStateSeed(a, 0);
  Chk('zero seed still generates', RandomStateNext(a) <> 0);

  if fails = 0 then writeln('RANDOMSTATE OK') else begin writeln('FAILED ', fails); Halt(1); end;
end.

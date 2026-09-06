program TestCoStackGuard;
{ THREE OVERFLOW SHAPES, THREE OUTCOMES, and the point is that two of them must
  report DIFFERENTLY -- the canary and the stack-pointer range check have
  different apertures and a change that collapsed them would still pass a test
  that only asserted "it aborts".

    safe  a frame that fits           -> runs to completion
    grad  recursion walking down      -> clobbers the CANARY word, rc 217
    leap  one frame past the canary   -> canary intact, SP below base, rc 217

  `leap` is the row that did not exist before 2026-09-06: a 12 KB frame on an
  8 KB stack steps over the one-word canary, so the yield-time check read
  correct and the program exited 0 having written below its own stack base.
  Measured then: frames of 10/12/14 KB all exited 0 while an 8 KB frame
  faulted -- a LARGER overflow caught LESS often than a smaller one, because
  what decided it was heap layout. feature-tls-provider-abstraction }
uses scheduler;

var gMode: ShortString;

function Walk(n: Integer): Int64;
var pad: array[0..127] of Int64;    { ~1 KB per frame }
    i: Integer;
begin
  for i := 0 to 127 do pad[i] := n + i;
  if n <= 0 then Walk := pad[0] else Walk := pad[1] + Walk(n - 1);
end;

function Leap: Int64;
var big: array[0..1535] of Int64;   { 12 KB in ONE frame }
begin
  big[0] := $5A5A5A5A;
  { YIELD WITH THE OVERSIZED FRAME STILL LIVE. The check reads where sp SITS at
    the yield, so this is its whole aperture: the same function returning first
    puts sp back inside the stack and is NOT caught -- measured 2026-09-06, and
    stated here because a reader who assumes otherwise will trust this test for
    a case it does not cover. That variant is contained (the write lands in the
    scheduler's own slack, not a neighbour) and undiagnosed. }
  CoYield;
  Leap := big[0];
end;

procedure Body(arg: Pointer);
var v: Int64;
begin
  writeln('body-in');
  if gMode = 'grad' then v := Walk(9)
  else if gMode = 'leap' then v := Leap
  else v := Walk(2);
  writeln('body-tail ', v mod 7);
  CoYield;                           { the checkpoint both guards are read at }
  writeln('body-out');
end;

begin
  gMode := 'safe';
  if ParamCount >= 1 then gMode := ParamStr(1);
  SpawnSized(@Body, nil, 8192);
  RunUntilDone;
  writeln('guard-ok');
end.

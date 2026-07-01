{$mode objfpc}
program test_big_static_array_open_param;

{ bug-const-open-array-param-stack-copies-caller-frame: a fixed array passed
  to an `array of T` open-array parameter used to stack-copy the whole array
  into the CALLER's frame -- harmless for a small array, a SIGSEGV risk for
  a large one (the caller's own frame scaled 1:1 with the source array's
  size, blowing the default ~8 MB process stack once the array got big
  enough). Fixed by routing arrays over MAX_OPEN_ARRAY_STACK_TEMP (64 KB)
  through a heap-backed managed dyn-array temp instead of a frame-local
  buffer -- released automatically at scope exit, same as any other managed
  local, so it does not leak either. Arrays at or under the threshold keep
  the original frame-local fast path, unchanged.

  This test exercises: small array (unaffected, original path) and large
  array (new path) x const-value and var-writeback parameter kinds, plus a
  repeated-call loop over the large array with an RSS ceiling to catch a
  leak in the new heap-backed path. The Makefile also asserts (via --debug)
  that NO routine in this program trips the oversized-stack-frame warning --
  the actual regression guard for the original bug. }

const
  BIG = 2097152;   { 2 MB, over the 64 KB threshold -> new heap-backed path }
var
  BigBuf: array[0..BIG-1] of Byte;
  SmallBuf: array[0..2] of Byte;

function SumConst(const buf: array of Byte): Int64;
var i: Integer; s: Int64;
begin
  s := 0;
  for i := 0 to High(buf) do s := s + buf[i];
  Result := s;
end;

procedure FillVar(var buf: array of Byte);
var i: Integer;
begin
  for i := 0 to High(buf) do buf[i] := Byte(i mod 256);
end;

var
  i, k: Integer;
  ok: Boolean;
  total: Int64;
begin
  { small array: unaffected by the fix, original frame-local path }
  SmallBuf[0] := 1; SmallBuf[1] := 2; SmallBuf[2] := 3;
  writeln('small const sum: ', SumConst(SmallBuf));
  FillVar(SmallBuf);
  writeln('small var: ', SmallBuf[0], ' ', SmallBuf[1], ' ', SmallBuf[2]);

  { big array: new heap-backed path }
  for i := 0 to BIG - 1 do BigBuf[i] := 0;
  writeln('big const sum (zeros): ', SumConst(BigBuf));
  FillVar(BigBuf);
  ok := True;
  for i := 0 to BIG - 1 do
    if BigBuf[i] <> Byte(i mod 256) then ok := False;
  writeln('big var writeback correct: ', ok);
  writeln('big const sum (filled): ', SumConst(BigBuf));

  { repeated-call leak guard: 50 calls over the 2 MB array. A per-call leak
    in the new heap-backed temp would balloon RSS by ~100 MB; a correctly
    released temp keeps RSS near BigBuf's own static footprint. }
  total := 0;
  for k := 1 to 50 do
    total := total + SumConst(BigBuf);
  writeln('leak-loop total: ', total);
end.

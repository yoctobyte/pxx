program test_xtensa_frame_over_32k;
{ A stack frame larger than 32 KB. xtensa lowers sp with ADDMI, whose immediate
  is a multiple of 256 and reaches only -32768, so ONE of them cannot allocate
  this frame -- the prologue now reserves several slots and emits a CHAIN.

  BOTH ABIS ARE THE POINT, and they failed differently, which is why one row is
  not enough: Call0 raised a clean "stack frame too large (> 32 KB)" error,
  while WINDOWED had no check at all and EncodeXtensaAddmi masks its immediate
  with `(imm div 256) and $FF` -- so windowed silently encoded a different,
  smaller adjustment and handed the body a frame that was not there. A loud
  bound and a silent wrap are the same defect wearing two faces.

  The sums are what catch a wrong adjustment rather than a rejected one: a frame
  that is short, or allocated in the wrong direction, corrupts the caller's
  locals or the saved registers, and `outer` is here to be corrupted. Touching
  the first, middle and last element of each array is what makes the whole span
  load-bearing instead of just the base.
  bug-a-xtensa-frame-larger-than-32kb-needs-more-than-one-addmi }

function Big(seed: Integer): Integer;
var
  buf: array[0..40000] of Byte;    { ~40 KB: past ADDMI's single-instruction reach }
  i, acc: Integer;
begin
  for i := 0 to 40000 do buf[i] := Byte((i + seed) and $FF);
  acc := 0;
  acc := acc + buf[0] + buf[20000] + buf[40000];
  Big := acc;
end;

function Bigger(seed: Integer): Integer;
var
  a: array[0..40000] of Byte;      { two of them: ~80 KB, so the chain is 3 deep }
  b: array[0..40000] of Byte;
  i, acc: Integer;
begin
  for i := 0 to 40000 do begin a[i] := Byte((i + seed) and $FF); b[i] := Byte((i * 2 + seed) and $FF); end;
  acc := a[0] + a[20000] + a[40000] + b[0] + b[20000] + b[40000];
  Bigger := acc;
end;

{ the small-frame boundary row: ADDI's own reach, which must not regress }
function Small(seed: Integer): Integer;
var t: array[0..7] of Byte; i, acc: Integer;
begin
  for i := 0 to 7 do t[i] := Byte(i + seed);
  acc := 0; for i := 0 to 7 do acc := acc + t[i];
  Small := acc;
end;

var outer: array[0..15] of Integer; i: Integer;
begin
  for i := 0 to 15 do outer[i] := 1000 + i;
  WriteLn('big    ', Big(1));
  WriteLn('bigger ', Bigger(1));
  WriteLn('small  ', Small(1));
  { the caller's locals must be untouched by any of the three frames }
  WriteLn('outer  ', outer[0], ' ', outer[15]);
end.

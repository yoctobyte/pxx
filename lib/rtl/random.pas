unit random;
{ Interim 32-bit PRNG for the demo apps. Numerical-Recipes linear-congruential
  generator: deterministic and reproducible from a seed, byte-identical across
  targets. Uses only ops the pinned stable supports (mul/add/and/or, small
  shifts).

  WHY 32-bit LCG and not the planned xoshiro256** (feature-random-library):
  the pinned stable (v9) has 64-bit gaps that block a modern 256-bit-state /
  64-bit-output generator -- `xor` operator unrecognized, `shl`/`shr` by >= ~31
  return 0, 64-bit hex literals truncate to 32 bits. See
  bug-64bit-shift-xor-literal-gaps. Upgrade once those land.

  Track B (libraries); built only with the pinned stable compiler. }

interface

{ Reseed the generator. Any 32-bit value; reproducible thereafter. }
procedure RandSeed(seed: LongWord);

{ Raw 32-bit output; advances the state. }
function RandU32: LongWord;

{ 0 .. n-1 (FPC-compatible Random(n)). n <= 0 yields 0. Uses the high bits,
  which are the well-distributed ones in an LCG. }
function Random(n: Integer): Integer;

{ Inclusive lo..hi. }
function RandRange(lo, hi: Integer): Integer;

implementation

var state: LongWord;

procedure RandSeed(seed: LongWord);
begin
  state := seed;
end;

function RandU32: LongWord;
begin
  state := state * 1664525 + 1013904223;
  RandU32 := state;
end;

function Random(n: Integer): Integer;
var v, nn: LongWord;
begin
  if n <= 0 then
  begin
    Random := 0;
    Exit;
  end;
  nn := n;
  v := RandU32 shr 16;          { high 16 bits: the random ones in an LCG }
  Random := Integer(v mod nn);
end;

function RandRange(lo, hi: Integer): Integer;
begin
  if hi < lo then RandRange := lo
  else RandRange := lo + Random(hi - lo + 1);
end;

initialization
  state := 2463534242;          { lively nonzero default before any RandSeed }
end.

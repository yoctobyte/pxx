unit random;
{ PRNG library. Two generators coexist:

  1. Xoshiro256** — 256-bit state, 64-bit output. High quality, the default
     for hosted targets. Seeded via SplitMix64 from a 64-bit seed.
     Deterministic and byte-identical across targets from the same seed.

  2. LCG (Numerical Recipes) — 32-bit state/output. Small and fast, suited
     for constrained targets (ESP32 etc). Deterministic and reproducible.

  The public surface (Random, RandSeed, RandRange) delegates to xoshiro.
  The LCG remains available directly for platforms that prefer it.

  Track B (libraries); built only with the pinned stable compiler. }

interface

{ --- Xoshiro256** (default on hosted) --- }

{ Seed xoshiro via SplitMix64 expansion. Reproducible thereafter. }
procedure XoshiroSeed(seed: UInt64);

{ Raw 64-bit output; advances xoshiro state. }
function XoshiroNext: UInt64;

{ --- LCG (lightweight, 32-bit) --- }

{ Reseed the LCG. Any 32-bit value; reproducible thereafter. }
procedure LCGSeed(seed: LongWord);

{ Raw 32-bit LCG output; advances state. }
function LCGNext: LongWord;

{ --- Public surface (delegates to xoshiro) --- }

{ Reseed the default generator (xoshiro). Accepts a 32-bit value for
  FPC compatibility; zero-extends to 64 bits for SplitMix64. }
procedure RandSeed(seed: LongWord);

{ 0 .. n-1 (FPC-compatible Random(n)). n <= 0 yields 0. }
function Random(n: Integer): Integer;

{ Inclusive lo..hi. }
function RandRange(lo, hi: Integer): Integer;

implementation

{ ===== SplitMix64 — seed expander ===== }

var sm_state: UInt64;

function SplitMix64Next: UInt64;
var z: UInt64;
begin
  sm_state := sm_state + UInt64($9E3779B97F4A7C15);
  z := sm_state;
  z := (z xor (z shr 30)) * UInt64($BF58476D1CE4E5B9);
  z := (z xor (z shr 27)) * UInt64($94D049BB133111EB);
  SplitMix64Next := z xor (z shr 31);
end;

{ ===== Xoshiro256** ===== }

var xs0, xs1, xs2, xs3: UInt64;

procedure XoshiroSeed(seed: UInt64);
begin
  sm_state := seed;
  xs0 := SplitMix64Next;
  xs1 := SplitMix64Next;
  xs2 := SplitMix64Next;
  xs3 := SplitMix64Next;
end;

function RotL64(x: UInt64; k: Integer): UInt64;
begin
  RotL64 := (x shl k) or (x shr (64 - k));
end;

function XoshiroNext: UInt64;
var t: UInt64;
begin
  t := RotL64(xs1 * 5, 7) * 9;
  XoshiroNext := t;
  t := xs1 shl 17;
  xs2 := xs2 xor xs0;
  xs3 := xs3 xor xs1;
  xs1 := xs1 xor xs2;
  xs0 := xs0 xor xs3;
  xs2 := xs2 xor t;
  xs3 := RotL64(xs3, 45);
end;

{ ===== LCG ===== }

var lcg_state: LongWord;

procedure LCGSeed(seed: LongWord);
begin
  lcg_state := seed;
end;

function LCGNext: LongWord;
begin
  lcg_state := lcg_state * 1664525 + 1013904223;
  LCGNext := lcg_state;
end;

{ ===== Public surface (xoshiro-backed) ===== }

procedure RandSeed(seed: LongWord);
begin
  XoshiroSeed(UInt64(seed));
end;

function Random(n: Integer): Integer;
var v: UInt64;
begin
  if n <= 0 then
  begin
    Random := 0;
    Exit;
  end;
  v := XoshiroNext shr 33;
  Random := Integer(v mod UInt64(n));
end;

function RandRange(lo, hi: Integer): Integer;
begin
  if hi < lo then RandRange := lo
  else RandRange := lo + Random(hi - lo + 1);
end;

initialization
  lcg_state := 2463534242;
  XoshiroSeed(UInt64($A39B3C2D1E0F4857));
end.

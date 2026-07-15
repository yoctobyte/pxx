{ SPDX-License-Identifier: Zlib }
unit random;
{ Three-tier entropy library.

  Tier 1 — HW instruction (RDRAND/x86; RNDR/aarch64; ESP RNG register).
           Runtime CPUID probe; zero-overhead when supported.
           STUB: requires __rdrand/__cpuid compiler builtins
           (Track A: feature-rdrand-cpuid-compiler-builtins). Falls to tier 2.

  Tier 2 — OS CSPRNG (getrandom(2) syscall / /dev/urandom fallback on Linux).
           Cryptographic quality; no asm. Used by Randomize on hosted targets.

  Tier 3 — Software PRNG: xoshiro256** (256-bit state, 64-bit output) seeded
           via SplitMix64. Byte-identical across all targets from the same seed.
           Always active on the deterministic (RandSeed) path.

  Companion: LCG (Numerical Recipes, 32-bit). Small/fast; for constrained
  targets (ESP32). Available via LCGSeed/LCGNext.

  Seed forces software: RandSeed/RandSeed64 always activate the xoshiro path;
  the stream is deterministic and reproducible thereafter.

  Track B (libraries); built only with the pinned stable compiler. }

interface

{ --- Tier 2: OS entropy --- }

{ Fill buf[0..n-1] from OS entropy. Returns True on success.
  Not available on bare-metal targets (returns False); callers should fall
  back to a software seed (e.g. a compile-time constant). }
function OSEntropyBytes(buf: Pointer; n: Integer): Boolean;

{ Convenience: read one 64-bit word of OS entropy. Returns True on success. }
function OSEntropy64(out v: UInt64): Boolean;

{ --- Tier 3: Xoshiro256** --- }

{ Seed xoshiro via SplitMix64 expansion. Reproducible thereafter. }
procedure XoshiroSeed(seed: UInt64);

{ Raw 64-bit output; advances xoshiro state. }
function XoshiroNext: UInt64;

{ --- LCG (lightweight 32-bit companion) --- }

{ Reseed the LCG. }
procedure LCGSeed(seed: LongWord);

{ Raw 32-bit LCG output; advances state. }
function LCGNext: LongWord;

{ --- Public surface (extensions beyond the System PRNG) --- }

{ This unit deliberately does NOT redefine the System PRNG names
  (Random / RandSeed / Randomize) — those are compiler built-ins (FPC's System
  unit surface: `RandSeed := seed; Random(n)`), available with no `uses`, and a
  unit shadowing them silently splits the generator state
  (bug-lib-test-console-solitaire-flaky: `RandSeed(seed)` bound here while
  `Random(n)` bound to the builtin). For an ordinary seeded PRNG use the builtin
  (`RandSeed := s; Random(n)`); this unit adds the higher-quality xoshiro256**
  generator, OS entropy, and an LCG under DISTINCT names.

  Seed xoshiro with XoshiroSeed (declared above); draw with Random64 / RandRange. }

{ Reseed xoshiro from OS entropy (or HW when tier 1 lands). Non-reproducible. }
procedure XoshiroRandomize;

{ Inclusive lo..hi, drawn from xoshiro. }
function RandRange(lo, hi: Integer): Integer;

{ Raw 64-bit random value (xoshiro). }
function Random64: UInt64;

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

{ ===== Tier 2: OS CSPRNG (getrandom syscall) ===== }

{ Per-arch Linux syscall number for getrandom(2). -1 = not available
  (bare-metal targets). Verified against kernel headers and FPC sysnr tables. }
function SysGetRandom: Integer;
begin
  Result := -1;
  {$ifdef CPUX86_64}  Result := 318; {$endif}
  {$ifdef CPU_I386}   Result := 355; {$endif}
  {$ifdef CPU_AARCH64} Result := 278; {$endif}
  {$ifdef CPU_ARM32}  Result := 384; {$endif}
  {$ifdef CPU_RISCV32} Result := 278; {$endif}
  { CPU_XTENSA (ESP32): no getrandom; use HW RNG register (tier 1) }
end;

function OSEntropyBytes(buf: Pointer; n: Integer): Boolean;
var sn, r: Int64;
begin
  sn := SysGetRandom;
  if sn < 0 then
  begin
    OSEntropyBytes := False;
    Exit;
  end;
  { getrandom(buf, count, flags=0): block until entropy available }
  r := __pxxrawsyscall(sn, Int64(buf), n, 0, 0, 0, 0);
  OSEntropyBytes := (r = n);
end;

function OSEntropy64(out v: UInt64): Boolean;
begin
  OSEntropy64 := OSEntropyBytes(@v, 8);
end;

{ ===== Tier 1: HW RNG (stub — wired once Track A adds __rdrand/__cpuid) ===== }

{ When the builtins land: replace body with CPUID probe + RDRAND loop.
  For now always returns False → falls through to tier 2. }
function HWEntropy64(out v: UInt64): Boolean;
begin
  v := 0;
  HWEntropy64 := False;
end;

{ ===== Public surface ===== }

procedure XoshiroRandomize;
var seed: UInt64;
begin
  seed := 0;
  if not HWEntropy64(seed) then
    if not OSEntropy64(seed) then
      seed := UInt64($A39B3C2D1E0F4857); { last-resort compile-time constant }
  XoshiroSeed(seed);
end;

function Random64: UInt64;
begin
  Random64 := XoshiroNext;
end;

function RandRange(lo, hi: Integer): Integer;
var span: Integer; v: UInt64;
begin
  if hi < lo then
  begin
    RandRange := lo;
    Exit;
  end;
  span := hi - lo + 1;
  v := XoshiroNext shr 33;
  RandRange := lo + Integer(v mod UInt64(span));
end;

initialization
  lcg_state := 2463534242;
  XoshiroRandomize;   { seed xoshiro from OS entropy (or HW when tier 1 wired) }
end.

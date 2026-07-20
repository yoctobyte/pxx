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

{ --- Explicit generator state (the thread-safe way) --- }

{ The functions above share ONE process-wide xoshiro state. That state is
  guarded by a lock, so calling them concurrently is safe — but it is a shared
  lock and a shared stream: two threads contend for it, and neither gets a
  reproducible sequence of its own, because the interleaving decides who draws
  what.

  For threaded work give each thread its OWN TRandomState. No lock is taken, no
  contention exists, and each stream is independently reproducible from its
  seed — which is what makes a parallel simulation repeatable. Derive the
  per-thread seeds with RandomStateSplit rather than seeding each from, say, its
  thread index: nearby seeds are exactly what SplitMix64 exists to decorrelate,
  and hand-picked ones are how correlated "random" streams get shipped. }
type
  TRandomState = record
    s0, s1, s2, s3: UInt64;
  end;

{ Seed a private state (SplitMix64 expansion, same as XoshiroSeed). }
procedure RandomStateSeed(var st: TRandomState; seed: UInt64);

{ Seed a private state from OS entropy. False (and a fallback seed) if entropy
  is unavailable, as on bare metal. }
function RandomStateRandomize(var st: TRandomState): Boolean;

{ Raw 64-bit draw; advances only `st`. No lock. }
function RandomStateNext(var st: TRandomState): UInt64;

{ Inclusive lo..hi drawn from `st`. }
function RandomStateRange(var st: TRandomState; lo, hi: Integer): Integer;

{ Derive an independent child stream from `parent`, advancing the parent. Use
  this to fan out one seed into N per-thread states. }
procedure RandomStateSplit(var parent: TRandomState; var child: TRandomState);

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

{ Spinlock over the SHARED generator (xs0..3, sm_state, lcg_state).

  A PRNG step is a handful of register operations, so a spinlock is the right
  shape — a futex round trip would cost more than the work it protects, and hold
  times are bounded by construction (no allocation, no syscall, no recursion
  inside the critical section).

  It exists because the alternative is worse than slow: two threads interleaving
  in XoshiroNext do not merely race for a value, they corrupt the state word by
  word and can leave the four registers correlated — a generator that keeps
  producing plausible-looking numbers while its stream quality has quietly
  collapsed. That is the failure mode this lock is here to prevent.

  Callers that care about throughput or reproducibility should use their own
  TRandomState instead and take no lock at all. }
var gRandLock: Integer = 0;

procedure RandLock;
begin
  while Integer(__pxxatomic_xchg(@gRandLock, 1)) <> 0 do ;
end;

procedure RandUnlock;
var ig: Integer;
begin
  ig := Integer(__pxxatomic_xchg(@gRandLock, 0));
  if ig = 0 then ;
end;

procedure XoshiroSeed(seed: UInt64);
begin
  RandLock;
  sm_state := seed;
  xs0 := SplitMix64Next;
  xs1 := SplitMix64Next;
  xs2 := SplitMix64Next;
  xs3 := SplitMix64Next;
  RandUnlock;
end;

function RotL64(x: UInt64; k: Integer): UInt64;
begin
  RotL64 := (x shl k) or (x shr (64 - k));
end;

{ The xoshiro256** step over an explicit state. Every generator path in this
  unit — shared and per-stream — goes through this one body, so there is exactly
  one copy of the algorithm to be right. }
function XoshiroStep(var a0, a1, a2, a3: UInt64): UInt64;
var t: UInt64;
begin
  t := RotL64(a1 * 5, 7) * 9;
  XoshiroStep := t;
  t := a1 shl 17;
  a2 := a2 xor a0;
  a3 := a3 xor a1;
  a1 := a1 xor a2;
  a0 := a0 xor a3;
  a2 := a2 xor t;
  a3 := RotL64(a3, 45);
end;

function XoshiroNext: UInt64;
var v: UInt64;
begin
  RandLock;
  v := XoshiroStep(xs0, xs1, xs2, xs3);
  RandUnlock;
  XoshiroNext := v;
end;

{ ===== LCG ===== }

var lcg_state: LongWord;

procedure LCGSeed(seed: LongWord);
begin
  RandLock;
  lcg_state := seed;
  RandUnlock;
end;

function LCGNext: LongWord;
var v: LongWord;
begin
  RandLock;
  lcg_state := lcg_state * 1664525 + 1013904223;
  v := lcg_state;
  RandUnlock;
  LCGNext := v;
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


{ ===== Explicit per-stream state ===== }

{ SplitMix64 over a caller-supplied word — the same expander the shared seeder
  uses, but with no shared state, so it is safe to call from any thread. }
function SplitMixOver(var w: UInt64): UInt64;
var z: UInt64;
begin
  w := w + UInt64($9E3779B97F4A7C15);
  z := w;
  z := (z xor (z shr 30)) * UInt64($BF58476D1CE4E5B9);
  z := (z xor (z shr 27)) * UInt64($94D049BB133111EB);
  SplitMixOver := z xor (z shr 31);
end;

procedure RandomStateSeed(var st: TRandomState; seed: UInt64);
var z: UInt64;
begin
  z := seed;
  st.s0 := SplitMixOver(z);
  st.s1 := SplitMixOver(z);
  st.s2 := SplitMixOver(z);
  st.s3 := SplitMixOver(z);
  { All-zero state is xoshiro's one fixed point: it would emit zeros forever.
    SplitMix64 makes it vanishingly unlikely, not impossible. }
  if (st.s0 or st.s1 or st.s2 or st.s3) = 0 then st.s0 := UInt64($9E3779B97F4A7C15);
end;

function RandomStateRandomize(var st: TRandomState): Boolean;
var seed: UInt64; ok: Boolean;
begin
  seed := 0;
  ok := HWEntropy64(seed);
  if not ok then ok := OSEntropy64(seed);
  if not ok then seed := UInt64($A39B3C2D1E0F4857);   { last-resort constant }
  RandomStateSeed(st, seed);
  RandomStateRandomize := ok;
end;

function RandomStateNext(var st: TRandomState): UInt64;
begin
  RandomStateNext := XoshiroStep(st.s0, st.s1, st.s2, st.s3);
end;

function RandomStateRange(var st: TRandomState; lo, hi: Integer): Integer;
var span: Integer; v: UInt64;
begin
  if hi < lo then
  begin
    RandomStateRange := lo;
    Exit;
  end;
  span := hi - lo + 1;
  v := RandomStateNext(st) shr 33;
  RandomStateRange := lo + Integer(v mod UInt64(span));
end;

procedure RandomStateSplit(var parent: TRandomState; var child: TRandomState);
begin
  { Seed the child from one draw of the parent, run back through SplitMix64 by
    RandomStateSeed. Consecutive children therefore start from parent outputs,
    which are already well separated — this is the documented way to fan out
    xoshiro streams without them sharing structure. }
  RandomStateSeed(child, RandomStateNext(parent));
end;


initialization
  lcg_state := 2463534242;
  XoshiroRandomize;   { seed xoshiro from OS entropy (or HW when tier 1 wired) }

end.

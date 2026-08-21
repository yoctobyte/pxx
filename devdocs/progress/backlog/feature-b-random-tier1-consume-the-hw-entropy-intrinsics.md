---
track: B
prio: 35
type: feature
blocked-by: []
summary: "The compiler now exports __pxxCpuHasHwRandom / __pxxHwRandom64 (x86-64 RDRAND behind a CPUID probe), which is what lib/rtl/random.pas's tier-1 stub has been waiting for. The library still runs one tier below its design; wiring it is a Track B change of a few lines."
status: backlog
owner: ""
---

# Wire random.pas's tier 1 to the hardware-entropy intrinsics

- **Track B** (`lib/rtl/random.pas`). The compiler half is done —
  [[feature-a-rdrand-cpuid-compiler-builtins]], landed 2026-08-21.
- Filed by Track A on landing it, because A does not own `lib/**`.

## What is available now

```pascal
function __pxxCpuHasHwRandom: Boolean;            { CPUID leaf 1 ECX bit 30, cached }
function __pxxHwRandom64(var v: UInt64): Boolean; { False = no entropy this time }
```

Both live in the compiler's `builtin` unit and are pulled in automatically by a
name pre-scan, so **`random.pas` needs no `uses` and no `{$ifdef}`** — which is
the point: [[feature-random-library]]'s mandate is one elegant `.pas` with the
per-arch instruction invisible to it.

## The one thing the wiring must get right

`__pxxHwRandom64` returning **False is normal**, not an error. RDRAND clears CF
and leaves the destination ZERO under load or entropy exhaustion. So the library
must bound its retries (Intel's guidance is ~10) and then **fall to tier 2**, and
must never treat the value alone as entropy — a silent zero in a CSPRNG seed is
the invisible catastrophic failure the `Boolean` exists to prevent.

## Targets

x86-64 answers truthfully; **every other target answers False**, which routes
the library to tier 2 automatically. That is the correct answer rather than a
stub, so no per-target branching is needed in the library at all.

aarch64 (`MRS RNDR`, gated on the optional FEAT_RNG), and the ESP RNG register,
are not implemented compiler-side yet — see the parent ticket for why. When they
land, this library code should need no change.

## Gate

Track B's: `make lib-test` / `make demos` with `$(PXX_STABLE)`, never rebuilding
the compiler. `test/lib_random.pas`'s SEEDED stream must stay byte-identical —
the deterministic path is seeded and by definition must not touch hardware
entropy. (Verified unchanged against `pinned` when the intrinsics landed.)

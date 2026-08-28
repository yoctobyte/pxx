---
track: B
prio: 40
type: feature
blocked-by: []
summary: "The compiler now exports __pxxCpuHasHwRandom / __pxxHwRandom64 (x86-64 RDRAND behind a CPUID probe), which is what lib/rtl/random.pas's tier-1 stub has been waiting for. The library still runs one tier below its design; wiring it is a Track B change of a few lines."
status: done
owner: frankB
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

## Resolved 2026-08-28 (Track B, frankB)

`lib/rtl/random.pas` tier 1 is live. `HWEntropy64` probes
`__pxxCpuHasHwRandom`, then retries `__pxxHwRandom64` up to
`HW_ENTROPY_RETRIES = 10` (Intel's guidance, named rather than a bare literal)
and falls to tier 2. On the give-up path `v` is re-zeroed before returning
False, because RDRAND leaves its destination zero on failure and a silent zero
reaching a CSPRNG seed is exactly the failure the Boolean exists to prevent.

No per-target branching, as the ticket predicted: x86-64 answers truthfully,
every other target answers False from the probe and routes itself to tier 2.
RNDR/ESP land compiler-side later and need no change here.

**One surface addition beyond the wiring.** The unit exported its tier-2 and
tier-3 probes but had no tier-1 interface section at all, so the tier could not
be tested from outside. Added `HWEntropyAvailable` and `HWEntropy64` to the
interface, symmetric with `OSEntropyBytes`/`OSEntropy64` directly below them.

### Measured, not assumed

The wiring is genuinely exercised on this box rather than passing through the
not-available branch: the probe answers TRUE, `/proc/cpuinfo` carries `rdrand`,
and three consecutive draws returned distinct 64-bit values. Worth stating
because a test that passes by taking the easy branch looks identical to one that
passes for the right reason.

`test/lib_random_hw_tier1.pas` asserts CONTRACTS, not values — RDRAND is present
here but not on every box the suite runs on — so both branches of the probe
print the same lines and the expected output is machine-independent. The line
with teeth is `seeded-reproducible`: tier 1 must not leak into the deterministic
path, where the damage would look random and therefore invisible.

Negative-controlled with a stuck source (`HWEntropy64` always returning a
constant): `contract=FAIL` and `randomize-varies=FAIL`, exit 1.

The ticket's stated gate holds: `test/lib_random.pas`'s seeded stream is
byte-identical against `test/lib_random.expected`, and `lib_randomstate` passes.

### The negative control caught a bug in my own test

The first draft printed `HWTIER1 OK` unconditionally. Against the stuck source
it produced two FAIL lines, then `HWTIER1 OK`, then **exit 0** — green to
anything reading the last line or the status, which is the third member of the
do-not-pipe family in `devdocs/dev/gating-and-waiting.md` appearing on the
producing side rather than the consuming one. A sentinel that failure can reach
is not a sentinel. The test now tracks an `allok` flag, prints `HWTIER1 FAIL`
and halts 1, and the Makefile compares the whole output rather than the tail, so
the FAIL lines survive as the diagnostic.

## Log
- 2026-08-28 — resolved, commit bf967b627.

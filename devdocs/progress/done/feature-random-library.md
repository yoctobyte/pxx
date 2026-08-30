---
track: B
prio: 45  # auto
blocked-by: []   # UNBLOCKED 2026-08-30 at ba14f5f56 for its four buildable targets. The ESP arm is split out as feature-random-esp-hw-tier and carries the soft-float edge; see "The ESP arm is elsewhere" at the end. Do NOT re-add an ESP edge here — it would park four working targets behind a bug they never touch.
owner: frankB
---

# Random library — HW/OS/software tiered RNG (cross-target capability test)

- **Type:** feature
- **Status:** done
  remaining work is HW tiers and thread-safe state)
- **Relation:** a real, reusable RTL library that doubles as a broad
  cross-target test: runtime capability probing, per-target inline asm, a
  syscall entropy path, procedural-type dispatch, an `initialization` section,
  and a deterministic software path that is byte-identical across all 6 targets
  (a perft-style oracle). Touches feature-threadsafe-io-serialization (global
  state under threads) and the ESP profiles (HW RNG register / esp_random).

## Goal

A `Random` unit that gives good random numbers with **no per-platform code from
the caller**: hardware RNG by default when available, OS CSPRNG otherwise,
software PRNG as the fallback — and the deterministic software PRNG whenever the
user seeds. Modern 256-bit-state / 64-bit-output internals, not a legacy
16/32-bit LCG. FPC-compatible surface so existing code (and the Lazarus line)
is unaffected.

## Three-tier entropy source (chosen once at unit init)

| Tier | Source | Selected when |
| --- | --- | --- |
| 1 — HW instruction | x86 `RDRAND`/`RDSEED`; aarch64 `RNDR` (FEAT_RNG); ESP RNG register / `esp_random` | capability probe says present |
| 2 — OS CSPRNG | `getrandom(2)` syscall (Linux, kernel-ABI — fits the no-libc design); `/dev/urandom` fallback | hosted, no usable HW instruction |
| 3 — Software PRNG | seeded from the best available tier above | fallback, **and forced whenever the user seeds** |

The init probe selects a backend and stores it in a **proc-typed var**
(indirect dispatch — exercises procedural types); the `initialization` section
runs the probe once.

## Seed forces software (key rule)

Hardware RNG is not reproducible or seedable. Therefore:
- `Randomize` → uses tier 1/2 (best available, non-reproducible).
- `RandomSeed(x)` / assigning `RandSeed` → switches to **tier 3 deterministic**
  so the stream is reproducible. This is intentional and documented, not a
  limitation.

## PRNG choice

**xoshiro256++** (256-bit state, 64-bit output) — modern, fast, well-tested.
(PCG64 acceptable alternative; decide in design.) No legacy LCG. The seeded
software stream is **identical across all targets** → the cross-target oracle.
Seed expansion via SplitMix64 from the user seed.

## API surface

**FPC-compatible (keep the Lazarus line):**
- `function Random: Double;` — [0,1)
- `function Random(L: Integer): Integer;` — [0, L)
- `procedure Randomize;`
- `RandSeed` variable (assignment → tier 3, reproducible)

**PXX extensions (on top):**
- `function Random64: UInt64;` / `function Random128: <128-bit>;`
- `procedure RandomBytes(var buf; n: Integer);`
- `function RandomRange(lo, hi: Int64): Int64;`
- `procedure RandomSeed(seed: UInt64);` (explicit deterministic entry)

## Per-target capability detail / landmines

- **x86-64 / i386:** `CPUID` leaf 1 ECX bit 30 = RDRAND; leaf 7 EBX bit 18 =
  RDSEED. `RDRAND` can **fail** (CF=0) → bounded retry loop, then fall to next
  tier. Inline asm (CPUID + RDRAND).
- **aarch64:** `RNDR`/`RNDRRS` are **optional** (FEAT_RNG); probe
  `ID_AA64ISAR0_EL1` RNDR field; `MRS` reads the system reg at EL0. Fall back if
  absent.
- **arm32:** no standard user HW RNG instruction → OS tier only.
- **riscv32 (user):** Zkr entropy source is an M-mode CSR, not user-accessible →
  OS tier (or ESP HW register on device).
- **ESP32 (xtensa / riscv32, bare + IDF):** read the RNG data register (bare) or
  `esp_random` (IDF). **Caveat:** ESP RNG is only truly random with the RF/WiFi
  clock enabled — document; do not claim CSPRNG quality in bare profile without
  it.
- **`getrandom`** may be absent (old kernel) or block at early boot → fall to
  `/dev/urandom`, then software.
- **Thread safety:** global PRNG state under threads → per-thread state or a
  lock (coordinate with feature-threadsafe-io-serialization).

## Testing strategy

- **Software path (seeded) — the deterministic oracle.** Fixed seed → a fixed
  stream; assert **byte-identical across all 6 targets** (cross-bootstrap-style
  run). This is the primary regression check.
- **HW / OS path — statistical smoke** (can't byte-compare true randomness):
  nonzero, varies run-to-run, rough uniformity over a large sample.
- **Capability matrix:** a debug override to force each tier; verify the init
  dispatch selects the right backend on each platform and that fallbacks chain
  correctly (HW-fail → OS → software).

## Design mandate: ONE elegant library file (arch hidden in the compiler)

Hard requirement: the unit is a **single elegant `.pas` file**, no per-arch
`{$ifdef}` soup. The per-target instruction mess (RDRAND opcodes, CPUID, RNDR
`MRS`, ESP RNG-reg address) lives in **`builtinheap` compiler intrinsics**, not
in the library. The library then reads clean:

```pascal
unit Random;
// 1. software PRNG core — pure Pascal (xoshiro256++ + SplitMix64). The bulk.
// 2. thin source dispatch (one-liners over intrinsics / syscall):
function HWRand64(out v: UInt64): Boolean;  // = __rdrand intrinsic; compiler emits per target
function OSRand64: UInt64;                  // = getrandom syscall
// software path = the PRNG core
```

`__rdrand`/`__cpuid`/`__rndr` resolve differently per target inside the
compiler; the `.pas` never sees an arch branch. (More elegant than FPC, whose
System-unit random is scattered per platform.)

## Compiler switch: preference, NOT a replacement for the safety fallback

A switch picks the **default UNSEEDED source** — e.g. `{$RNG AUTO|HARDWARE|
SOFTWARE}` (or `--rng=`):

- **AUTO** (default) — runtime probe: HW if present, else OS, else software. The
  portable, safe path.
- **SOFTWARE** — always the deterministic-capable PRNG. Smallest, fully
  reproducible.
- **HARDWARE** — prefer HW.

**Critical safety rule:** on portable (multi-CPU) binaries the switch must NOT
make HW purely compile-time — a `HARDWARE` binary on a CPU without RDRAND would
hit an illegal instruction. So in portable builds, `HARDWARE` still keeps the
**runtime probe + software fallback**. The switch tunes preference; it does not
delete the safety net.

**Exception — fixed platforms (ESP32):** the HW RNG is known to exist, so the
switch MAY **hard-select** HW and **elide the probe + software path** entirely →
smaller code. This is the embedded win: one library source, but on a known
target it compiles down to just the HW read.

**Orthogonal:** the seed rule (`RandSeed`/`RandomSeed` → software) is runtime
state, independent of the switch. The switch sets the *unseeded* default source;
seeding always flips to the deterministic PRNG. No conflict.

## Dependency: HW-instruction emission (and how to avoid blocking on it)

Tiers 1 (HW) need a few fixed CPU instructions emitted (CPUID, RDRAND, `MRS
RNDR`, ESP RNG-reg / MMIO read). **Tiers 2 (getrandom) and 3 (software) need no
asm at all** — so slices 1–3 ship a useful library before any asm work. Only
slices 4–6 touch instructions.

Two ways to satisfy the HW tier; **prefer the second:**

1. **General inline asm** (feature-inline-asm-depth) — currently x86-64-only +
   rudimentary. Heavy: needs a per-target asm frontend to mature. Over-kill for
   ~4 fixed sequences.
2. **Dedicated compiler intrinsics in `builtinheap`** (RECOMMENDED) — emit the
   fixed sequences directly via EmitB as builtins (`__rdrand`, `__cpuid`,
   `__rndr`, raw MMIO read), exactly like the existing `__pxxrawsyscall`. No
   asm-frontend dependency; reuses a proven mechanism; scoped to the handful of
   ops the lib needs.

So this ticket is **not hard-blocked** on feature-inline-asm-depth: slices 1–3
are asm-free, and slices 4–6 use intrinsics (option 2). Full inline-asm-depth is
only needed if a user writes arbitrary asm — out of scope here.

## Slices

1. **Software PRNG core** — xoshiro256++ + SplitMix64 seed; deterministic;
   cross-target byte-identical oracle. Pure, no platform code. Lands first.
2. **FPC surface** — `Random`/`Random(L)`/`Randomize`/`RandSeed` over the core.
3. **OS tier** — `getrandom` syscall (+ `/dev/urandom` fallback); used by
   `Randomize`.
4. **HW tier x86** — CPUID probe + RDRAND (+ retry); inline asm.
5. **HW tier aarch64** — RNDR probe + read.
6. **ESP tier** — RNG register (bare) / esp_random (IDF).
7. **Thread-safe state** — per-thread or locked (with the threadsafe-io work).

## Acceptance

`Random*` works with zero caller platform code; init auto-selects the best tier
per platform; seeding switches to a reproducible software stream that is
byte-identical across all 6 targets; HW/OS tiers pass statistical smoke; the
capability matrix shows correct selection + fallback chaining. FPC-surface
programs compile and run unmodified.

## Log
- 2026-06-18 — opened. Tiered HW→OS→software RNG with init-time capability probe
  (proc-typed dispatch), seed-forces-software rule, xoshiro256++ core, FPC
  surface + PXX extensions. Chosen as a broad cross-target test (CPUID/feature-
  reg probing, per-target HW-instruction emission, getrandom syscall,
  deterministic software oracle). Per-target landmines + dual-mode test
  (deterministic-software-oracle + statistical-HW) recorded.
- 2026-06-18 — clarified asm dependency: only HW tiers (slices 4–6) need
  instruction emission; tiers 2–3 (slices 1–3) are asm-free, so the lib ships
  useful first. HW tier should use dedicated `builtinheap` intrinsics
  (`__rdrand`/`__cpuid`/`__rndr`, à la `__pxxrawsyscall`), NOT block on the
  general feature-inline-asm-depth frontend. Not hard-blocked.
- 2026-06-19 — **interim software slice landed** (track B): `lib/rtl/random.pas`,
  a deterministic 32-bit Numerical-Recipes LCG (`RandSeed`/`RandU32`/`Random(n)`/
  `RandRange`), reproducible-from-seed, asserted in `make lib-test`. Uses an
  `initialization` section for a lively default seed. **NOT** the planned
  256-bit-state / 64-bit-output xoshiro256**: pinned v9 lacks the 64-bit ops
  needed (`xor`, large shifts, 64-bit hex literals) — see
  bug-64bit-shift-xor-literal-gaps. Upgrade the software tier to xoshiro256** +
  splitmix64 seeding once those land; HW/OS tiers (slices 4–6) still as scoped.
- 2026-06-20 — **xoshiro256** software core landed** (track B, slice 1 done):
  `lib/rtl/random.pas` upgraded from the interim LCG to xoshiro256** with
  SplitMix64 seed expansion. 64-bit ops (xor, large shifts, hex literals) now
  available on pinned v20. Output verified byte-identical against a C reference
  implementation. The LCG is retained alongside as `LCGSeed`/`LCGNext` for
  constrained targets (ESP32). Public surface (`RandSeed`/`Random(n)`/`RandRange`)
  now delegates to xoshiro. `RandU32` replaced by `XoshiroNext`/`LCGNext`.
  Slices 1–2 done (software core + FPC surface). Remaining: OS tier (slice 3),
  HW tiers (slices 4–6), thread safety (slice 7).
- 2026-06-28 — **OS tier landed** (track B, slice 3 done): `getrandom(2)` syscall fallback implemented via `__pxxrawsyscall` on Linux. Verified that `Randomize` correctly varies between runs, and deterministic seeded path remains byte-identical.
- 2026-06-28 — parked from `unfinished/` back to backlog after cleanup. Verified
  `test/lib_random.pas` still prints the expected deterministic seeded streams.
  Resume at slice 4: dedicated compiler intrinsics for CPUID/RDRAND (or the
  target-specific HW tiers), then thread-safe state.

## Log
- 2026-07-20 — **Slice 7 (thread-safe state) landed** (Track B, `lib/rtl/random.pas`).
  Slices 4-6 (HW tiers: RDRAND/RDSEED, aarch64 RNDR, ESP RNG) remain blocked —
  they need `rdrand`/`cpuid`/`rndr` from inline asm, and the asm frontend has
  none of them: see [[feature-inline-asm-xmm-operands]], which now tracks the
  whole missing-mnemonic surface including `cpuid`.

  Two halves, because "thread-safe" alone would have been the wrong answer:

  **The shared generator is now locked.** `xs0..3`, `sm_state` and `lcg_state`
  sit behind a spinlock (`__pxxatomic_xchg`). A spinlock is the right shape here
  — a PRNG step is a few register ops, so a futex round trip would cost more
  than the work it guards, and hold times are bounded by construction. The
  failure it prevents is worse than a lost value: two threads interleaving in
  `XoshiroNext` corrupt the state word by word and can leave the four registers
  correlated, so the generator keeps emitting plausible numbers while its stream
  quality has quietly collapsed.

  **`TRandomState` is the answer for threaded work.** A lock makes the shared
  generator safe but it is still one contended stream, and — the part that
  matters for simulation — no thread gets a reproducible sequence, because the
  interleaving decides who draws what. So there is now an explicit per-stream
  API: `RandomStateSeed` / `RandomStateRandomize` / `RandomStateNext` /
  `RandomStateRange` / `RandomStateSplit`. No lock, no contention, and each
  stream replays exactly from its seed. `RandomStateSplit` is the documented way
  to fan one seed into N per-worker states; seeding each worker from its index
  instead is precisely the correlated-streams mistake SplitMix64 exists to avoid.

  Both generator paths now go through one `XoshiroStep` body, so there is a
  single copy of the algorithm rather than one per call site.

  Gated: `test/lib_randomstate.pas` in `make lib-test` (single-threaded and
  bounded) covers seed reproducibility, divergence, split distinctness, split
  reproducibility, range bounds and uniformity, and the all-zero-state fixed
  point that xoshiro would otherwise never escape.

  **What the threaded check does and does not prove:** 200k concurrent draws
  across 8 workers produce no zero outputs and leave the shared stream healthy.
  That is evidence of coherence, not a proof of it — a lost update does not
  crash, it degrades distribution, and detecting that reliably needs a
  statistical battery this repo does not have yet. The lock's correctness rests
  on the argument above; the test is a regression guard, not the justification.

## Blocked (2026-07-20)

Slices 1-3 and 7 are done. Slices **4-6 are the HW entropy tiers** and every one
of them needs an instruction the asm frontend cannot encode: `rdrand`/`rdseed`
(x86), `rndr` (aarch64 FEAT_RNG), and on ESP the RNG register read. The frontend
has no `cpuid` either, so the capability probe those tiers need is equally
unreachable — this is not "not written yet", it is not expressible.

`blocked-by: feature-inline-asm-xmm-operands`, which now tracks the whole missing
mnemonic surface including `cpuid`. Nothing further is available in this lane.



---

## Track B portion COMPLETE 2026-08-15; what remains is Track A

### Landed

- **Two real defects fixed in `RandRange`**, both measured, not argued:
  - **Modulo bias.** `lo + (Next shr 33) mod span` skewed a wide span badly —
    over 2,000,000 draws of `RandRange(0, 1499999999)`, the low 43.17% of the
    range collected **60.23%** of results. Small spans hid it (a d6 is off by
    ~3e-9), which is how it survived in a library whose entire purpose is
    distribution quality. Replaced with masked rejection: **43.19%** measured,
    against 43.17% ideal, and chi-square 6.36 on 16 bins over 1.6M draws
    (15 dof, expect ~15).
  - **Overflow crash.** `span := hi - lo + 1` in Integer wraps to 0 for the full
    range, so `RandRange(Low(Integer), High(Integer))` divided by zero and
    raised **EDivByZero**. The span is a UInt64 from Int64 operands now and the
    whole range is legal.
- **API completed** per the surface above: `RandRange64` (full Int64 span,
  including the degenerate whole-of-Int64 case where no rejection is possible),
  `RandomDouble` (53-bit [0,1) — note this is NOT the builtin `Random: Double`,
  which is the legacy LCG), `RandomBytes`, and the per-state siblings
  `RandomStateRange64` / `RandomStateDouble` / `RandomStateBytes`.
- **Cross-target oracle verified.** The seeded stream is **byte-identical on
  x86-64, i386, aarch64 and arm32**, which is what this ticket wanted the
  software tier to be. `test/lib_random.expected` pins it.
- Thread-safe state was already done (shared state under a lock; `TRandomState`
  for per-thread streams with no lock and independent reproducibility).

### Remaining, and none of it is Track B

**Re-measured 2026-08-28 (frankB). Two of the three entries below were stale;
the corrections follow each one.**

- **Tier 1 (hardware entropy)** needs compiler intrinsics, because the design
  mandate keeps per-arch instructions out of the `.pas`. The source cited
  `feature-rdrand-cpuid-compiler-builtins`, which **had never been filed** —
  now [[feature-a-rdrand-cpuid-compiler-builtins]].
- **riscv32 cannot build this unit at all**: the shared state's lock needs
  atomics the core has no instruction for, and the compiler refuses with a clear
  message rather than miscompiling. [[bug-a-riscv32-and-xtensa-have-no-atomic-codegen]]
  (marked done, but this unit still does not build — worth re-checking against
  that record). So the cross-target oracle covers 4 targets, not 6.
- **`Random128`** from the API sketch is not implemented: there is no 128-bit
  integer type to return. Left out deliberately rather than faked with a record.


---

**Unblocked and moved to `backlog/` by the coordinator, 2026-08-28.** Its declared
`blocked-by` names a ticket that has since been resolved, so this was sitting in `blocked/` —
which `ready`/`next` never scan — while it was actually rankable. Nothing about the work
changed; only the record was stale. Found by a sweep (see
`chore-t-nothing-re-checks-a-blocked-by-edge-after-its-blocker-closes`); 14 tickets repo-wide
carry at least one `blocked-by` naming a closed ticket, five of them fully unblocked.

## 2026-08-28 (frankB) — the "Remaining" list re-measured

Checked rather than read, because this ticket was surfaced as available Track B
work and its remaining list is what makes that judgement.

**Tier 1 (hardware entropy) — DONE, both halves.** The compiler intrinsics
landed as [[feature-a-rdrand-cpuid-compiler-builtins]] (2026-08-21), and the
library was wired to them tonight in
[[feature-b-random-tier1-consume-the-hw-entropy-intrinsics]]: `HWEntropy64`
probes `__pxxCpuHasHwRandom`, retries `__pxxHwRandom64` a bounded ten times, and
falls to tier 2. Verified live on this box (probe TRUE, `rdrand` in
`/proc/cpuinfo`, three distinct draws) rather than passing through the
not-available branch, which looks identical from outside.

**"riscv32 cannot build this unit at all" — imprecise, and the correction
matters.** Measured today:

| invocation | result |
| --- | --- |
| `--target=riscv32 --platform=esp` | **builds, exit 0** |
| `--target=riscv32` (hosted/posix units) | fails on atomics: "machine-mode CSR access (mstatus), which a hosted user-mode program does not have" |

So the unit builds for the riscv32 configuration that actually ships (the C3 ESP
profile). The atomics refusal is specific to *hosted* riscv32. Worth noting my
first measurement used the default platform units and would have confirmed the
ticket's claim — it was wrong for the same reason a strace of glibc was wrong
earlier tonight: it measured a configuration nobody builds.

**xtensa fails too, on something this ticket does not mention.** Not atomics —
`error: target xtensa: unsupported node in IR codegen: syscall`, from tier 2's
`__pxxrawsyscall`, which is **statically unreachable on xtensa** because
`SysGetRandom` returns -1 there. The library is correct; the compiler refuses to
lower dead code. Filed as
[[bug-a-xtensa-refuses-to-lower-an-unreachable-syscall]] (Track A, prio 45) and
deliberately NOT worked around here — wrapping the call in `{$ifdef}` would be
the compiler-appeasement workaround, and xtensa is the primary ESP target, so
the cost of the gap is real.

**`Random128`** is unchanged: still deliberately absent, no 128-bit integer type
to return.

### Net effect on this ticket's rankability

Nothing here is Track B work. Tier 1 is closed; the two remaining items are a
Track A codegen gap (xtensa) and a hosted-riscv32 atomics limitation that no
shipping configuration hits. The cross-target oracle covers 4 targets, and the
honest count of what is *blocked* is one target, not two.


## Second blocker recorded 2026-08-28 — it was live and unedged

frankB re-verified this ticket live and found it unworkable: the Track B portion has
been done since 2026-08-15 and the remaining HW tier is Track A, but on top of that
`bug-a-xtensa-refuses-to-lower-an-unreachable-syscall` — which frankB itself filed —
is still open and blocks it.

**That edge was never recorded, so the ranker showed this ticket as READY at p45 in
Track B's queue and the coordinator dispatched a session onto it.** Adding it now.

> **A ranked queue says a ticket is UNBLOCKED, not that it has WORK LEFT IN IT.**
> Those are different claims and the board only checks the first.


## Blockers re-verified at pin v395, 2026-08-30 (frankB)

Asked by the coordinator to check whether the two recorded blockers were still
true at HEAD, since a blocker that was fixed and never unlinked holds a ticket
as effectively as a real one. **Both are closed and both fixes hold.** Neither
is the reason this is still unbuildable.

- [[bug-a-xtensa-refuses-to-lower-an-unreachable-syscall]] — the
  `unsupported node in IR codegen: syscall` error is **gone**. xtensa now gets
  further and stops on a different symbol entirely.
- [[feature-a-rdrand-cpuid-compiler-builtins]] — the intrinsics exist and work
  on **x86-64, aarch64, arm32 and i386**, verified with a five-line program
  that names `__pxxCpuHasHwRandom` and nothing else.

**A new wall stood behind the old one**, and it is filed as
[[bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target]] (A+S,
p45), now this ticket's only `blocked-by:` edge. `pasparser_prog.inc:1056`
excludes `__pxxCpuHasHwRandom` / `__pxxHwRandom64` from the builtin-unit pull
with `and (not TargetIsEspClass)`, so naming either on an ESP target is
`error: undefined variable`. `random.pas:321` names it unconditionally — as its
mandate requires — so **this unit does not compile on xtensa or riscv32 at all**,
which is a harder statement than "tier 1 is missing there".

Measured with a driver that only does `v := Random64`, and — the part without
which none of it means anything — **against a control**: an empty program with
no `uses random` builds fine under `--esp-profile=bare` on both ESP targets, and
fails identically to the driver on the non-bare ESP profile (`calloc`, an
external-symbol limitation belonging to any program on that profile). So the
non-bare failures are not this unit's, and only the `bare` rows isolate a real
defect. Hosted riscv32 also builds an empty program, which is what makes its
`atomics need machine-mode CSR access` failure genuinely this unit's — the
separate limitation already recorded above, still true, still hitting no
shipping configuration.

**Still nothing here for Track B.** The remaining work is a Track A decision
about the builtin unit on ESP (three options are laid out in the new ticket),
and the `{$ifdef}` that would make `random.pas` compile today is exactly the
compiler-appeasement workaround the platonic-code rule forbids.


## The ESP arm is elsewhere — read this before adding a blocker (frankB, 2026-08-30)

This ticket is **unblocked and claimable for x86-64, aarch64, arm32 and i386**.
`uses random` builds on all four, verified at `ba14f5f56` with a driver whose
body is `v := Random64` and a second using `RandomDouble`.

**It does not build on bare xtensa or bare riscv32, and that is deliberately
NOT recorded here.** The ESP arm is split out as
[[feature-random-esp-hw-tier]] (B+S, p40), which carries the real
`blocked-by` edge to
[[bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help]].

**Do not "fix" that by adding the edge to this ticket.** `blocked-by:` has no
notion of *partial* — the ranker reads it as "do not claim" — so one edge here
would park the four working targets behind a soft-float bug they never touch.
That is over-blocking, and it is worse than the alternative because it is
silent and total. The split exists precisely so each half has a status that can
be true, and this paragraph is the ESP half's presence in the ranked queue.

### What remains here

The HW tiers and thread-safe state, on the four buildable targets.
[[feature-a-rdrand-cpuid-compiler-builtins]] shipped the intrinsics and
[[bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target]] made
them reachable everywhere, so tier 1 is now a library question rather than a
compiler one.

### The blocker history, so nobody re-walks it

Three walls, in order, each visible only once the previous one fell — which is
why "the blocker closed" was never the same claim as "it builds":

1. `bug-a-xtensa-refuses-to-lower-an-unreachable-syscall` — closed, fix holds.
2. `feature-a-rdrand-cpuid-compiler-builtins` — closed, and the intrinsics work
   on all four non-ESP targets.
3. `bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target` —
   filed 2026-08-30 when the first two turned out not to be why this was
   unbuildable, fixed the same day at `ba14f5f56`.

Behind all three, on ESP only, is the soft-float wall now carried by the split
ticket. **Each of these was invisible until the one in front of it fell,
because the compiler stops at the first error** — which is the whole reason a
`done/` blocker is not evidence that the thing it blocked now works. The only
check that ever caught it was building the thing.

## 2026-08-30 (frankB) — RESOLVED. The remaining work was already done; verified, not read.

Claimed to do "the HW tiers and thread-safe state" — the words in this ticket's
own status line. **Both were already complete**, and the status line is what
was stale. Verified by running at `c781fc84f` / pin v396, because this ticket's
whole history is of records that were true when written.

| claim | how it was checked | result |
| --- | --- | --- |
| software tier, cross-target oracle | `test/lib_random.pas` diffed against `test/lib_random.expected` | **matches** |
| thread-safe state (slice 7, landed 2026-07-20) | `test/lib_randomstate.pas`, the `lib-test` gate | **RANDOMSTATE OK** |
| tier 1 wired to the intrinsics | ran it: `HWEntropyAvailable` → TRUE, three `HWEntropy64` draws all distinct, `rdrand` present in `/proc/cpuinfo` | **live, on the AVAILABLE branch** |
| the four oracle targets still build | `lib_random.pas` compiled for x86-64, i386, aarch64, arm32 | **all four build** |

The tier-1 row is the one that needed *running* rather than compiling: the
not-available branch returns cleanly and looks identical from outside, so a
build check would have passed on a machine where the intrinsic never fires.

### Why this closes rather than shrinking

Everything in the API sketch is implemented and gated. What is left is not work
this ticket can hold:

- **`Random128`** — deliberately absent, unchanged since the sketch: there is
  no 128-bit integer type to return, and faking it with a record would be a
  worse answer than not having it. That is a settled decision, not a gap.
- **Hosted riscv32** — still `atomics need machine-mode CSR access (mstatus),
  which a hosted user-mode program does not have`, re-confirmed today. No
  shipping configuration builds hosted riscv32; the C3 ships the ESP profile.
- **Bare xtensa / riscv32** — split out as [[feature-random-esp-hw-tier]] with a
  real `blocked-by` edge to
  [[bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help]].

### The thing this ticket kept teaching, one last time

Three Track A walls fell in front of it (`syscall` lowering, the missing
intrinsics ticket, the ESP-unreachable intrinsics), each invisible until the
one ahead of it did — the compiler stops at the first error. Then the work
behind them turned out to have been finished weeks earlier, and only the
summary line said otherwise.

**A ticket's status line is a claim with a date on it, and so is its
"Remaining" section.** This one's remaining list was re-measured on 2026-08-28
and two of its three entries were already stale then; today the whole list is.
Nothing here was ever wrong when written.

Gate: `make lib-test`'s two random entries green, unchanged, plus the live
tier-1 check above. No source changed — this ticket closes on verification, not
on a fix.
- 2026-08-30 — resolved, commit d56be6647.

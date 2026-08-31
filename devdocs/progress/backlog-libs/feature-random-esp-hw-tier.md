---
track: B+S
prio: 40
blocked-by: [bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help]   # CONFIRMED 2026-08-30 at c781fc84f, after the entropy fix landed — see "Status of the presumed blocker". Filed with no edge because it did not reproduce; the edge is here now because a run showed it.
type: feature
summary: "The ESP arm of feature-random-library, split out so the parent stays claimable for its four buildable targets: the ESP32 HW RNG register as tier 1, and Randomize's seeding on a bare boot that has no clock. Split proposed by the coordinator on the correct ground that the ranker's blocked-by has no notion of PARTIAL — but the blocker that motivated the split does not reproduce here, so this ships with no edge and a stated measurement to settle it."
status: backlog
owner: unassigned
---

# Random library — the ESP hardware tier

- **Type:** feature (library + SoC) — **Track B** file ownership, **S** tag.
- **Filed:** 2026-08-30 by frankB, splitting [[feature-random-library]] at the
  coordinator's proposal.
- Builds with `$(PXX_STABLE)`; no compiler rebuild.

## Why this is its own ticket

`feature-random-library`'s remaining work is the HW tiers and thread-safe
state. Four targets (x86-64, aarch64, arm32, i386) can build the unit today and
their HW tier is ordinary Track B work. The ESP targets cannot, and their tier 1
is a different job — a peripheral register, not a CPU instruction.

Carrying both in one ticket forces the board to express "partially blocked",
**which `blocked-by:` cannot say**: the ranker reads it as "do not claim", with
no notion of partial, so one edge would park the four buildable targets behind
something they never touch. Splitting gives each half a status that can be
true. That division already existed in the work; the ticket was carrying both.

## Scope

1. **Tier 1 on ESP: the hardware RNG register.** `esp_random` / the RNG
   peripheral, reached the way the other tier-1 paths are — through a compiler
   intrinsic, not per-arch code in `random.pas`. The mandate is unchanged and
   is the whole reason the intrinsics are compiler-side:
   `lib/rtl/random.pas` contains no `{$ifdef}` per target.
   [[bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target]]
   made `__pxxCpuHasHwRandom` reachable on ESP; it answers **False** there, so
   ESP correctly falls to tier 2 today. This ticket is about making it answer
   True and mean it.
2. **`Randomize` on a bare boot.** Relayed from frankA, **not measured here**:
   `Randomize` seeds from a clock syscall, and a bare-profile boot has no clock
   to read. If that holds, the seed is constant across resets — every device
   produces the same sequence, which is the silent-wrong-answer shape rather
   than a failure. Confirm before designing: read what `Randomize` actually
   calls on `--esp-profile=bare` rather than trusting this paragraph.

## Status of the presumed blocker — CONFIRMED 2026-08-30, and the earlier negative is explained

The split was proposed so that
[[bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help]]
would have a ticket it could genuinely block: bare xtensa and bare riscv32 were
reported to fail `uses random` with *"no FPU ... `__pxx_ul2d` / `__pxx_l2d` is
not linked"*.

**UPDATE, same day, after `ba14f5f56` landed: the edge is CONFIRMED and is now
in the frontmatter.** The section below is left standing rather than rewritten,
because the reason the first attempt saw nothing is the useful part.

`uses random` on bare xtensa and bare riscv32 fails at
`lib/rtl/random.pas:460` — inside `RandomDouble` — with *"this target has no FPU
and the soft-float kernel `__pxx_ul2d` is not linked; add `uses softfloat` to
the program"*. Three things make it worse than the report suggested:

1. **It fires for programs that never touch a float.** The unit is compiled
   whole, so a driver whose body is only `v := Random64` hits `RandomDouble`'s
   float code anyway. The blocker is the **unit**, not `RandomDouble`.
2. **`uses softfloat` — the fix the diagnostic itself advises — does not
   work.** Measured in both orders on both targets. That is exactly
   [[bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help]],
   now with a concrete consumer.
3. **What DOES work is putting any float in the PROGRAM.** A driver that adds
   `d := 1.5; d := d * 2.0` alongside `v := Random64` builds on both targets.

Point 3 is the root cause and it is a shape this repo has just fixed once: the
soft-float kernel is pulled by a **token scan of the program**, so a need that
arises inside a *unit* is invisible to it. That is the identical defect
[[bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target]]
had, in a second place — and the fix has a template, since `ba14f5f56` solved
it for the intrinsics by making an on-demand unit a library file can `uses`.

### Why the first pass saw nothing — the confound, recorded so it is not repeated

**Every one of the seven shapes below is a PROGRAM with float code in it, so
each one pulled the kernel by the very mechanism that is broken.** They were
testing the working path while trying to test the broken one. The table stays
because it is still true and still bounds the failure — generic float on bare
ESP is fine — but it never could have found this: `random.pas:448` and `:568` do `Double(UInt64 shr 11) * 1.1102e-16`,
which is exactly a `__pxx_ul2d`, so the report is structurally plausible — and
seven separate float programs still build on **both** bare ESP targets at pin
v395:

| shape | bare xtensa | bare riscv32 |
| --- | --- | --- |
| `Double(u shr 11) * 1.1102e-16` — random.pas:448 verbatim | builds | builds |
| `UInt64` → `Double` assignment | builds | builds |
| `Int64` → `Double` assignment | builds | builds |
| `Double / Double` | builds | builds |
| `Trunc(Double)` → `Int64` | builds | builds |
| float multiply + add | builds | builds |
| **the same expression inside a UNIT**, called from a program | builds | builds |

Control: the identical programs with the float removed also build, so this is
not "bare ESP builds nothing".

**This is not a claim that the report is wrong.** It was made with the
intrinsic fix in place, and until that lands here `uses random` stops earlier —
at `random.pas:321`, `undefined variable (__pxxCpuHasHwRandom)` — and the
compiler never reaches the float code. So the two observations are compatible;
what they rule out is the *general* form. **If the wall is real it is narrower
than "bare ESP has no soft float"**, and that matters, because it changes
whether the soft-float ticket is even the right thing to block on.

### The one measurement that settles it

Against the **landed** sha, never a local tree:

```
stable_linux_amd64/default/pinned --target=xtensa  --platform=esp --esp-profile=bare \
    -Fulib/rtl <driver-using-random>.pas /tmp/out
stable_linux_amd64/default/pinned --target=riscv32 --platform=esp --esp-profile=bare \
    -Fulib/rtl <driver-using-random>.pas /tmp/out
```

with a driver whose body is `v := Random64` and, separately, one using
`RandomDouble` — because only the second reaches the float path, and if only
that one fails the blocker is `RandomDouble`, not the unit.

**The edge was added when a run showed the failure, and not before.** That
sequence is the point: filing it unmeasured would have been right by accident,
and the measurement changed *what* the blocker is (the unit, not
`RandomDouble`) and *why* (an ambient pull that cannot see into a unit), which
an assumed edge would have recorded wrongly while looking correct.

## Gate

`make lib-test` green, plus a cross build of a `uses random` driver for xtensa
and riscv32 under `--esp-profile=bare`, plus evidence the HW tier actually
returns entropy rather than a constant — a tier that silently returns zeros
passes every build gate there is.

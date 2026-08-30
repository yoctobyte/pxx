---
track: B+S
prio: 40
blocked-by: []   # NOT the soft-float ticket — see "Status of the presumed blocker". The edge was proposed and is UNCONFIRMED; adding it unmeasured would park this for nothing.
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

## Status of the presumed blocker — MEASURED, and it does not reproduce

The split was proposed so that
[[bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help]]
would have a ticket it could genuinely block: bare xtensa and bare riscv32 were
reported to fail `uses random` with *"no FPU ... `__pxx_ul2d` / `__pxx_l2d` is
not linked"*.

**That edge is NOT in the frontmatter, because it does not reproduce from
here.** `random.pas:448` and `:568` do `Double(UInt64 shr 11) * 1.1102e-16`,
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

**Add the `blocked-by` edge when a run shows the failure, and not before.**
An unmeasured edge parks work for nothing, which is the same defect as an
unrecorded one pointed the other way — and this ticket exists because of that
class of error.

## Gate

`make lib-test` green, plus a cross build of a `uses random` driver for xtensa
and riscv32 under `--esp-profile=bare`, plus evidence the HW tier actually
returns entropy rather than a constant — a tier that silently returns zeros
passes every build gate there is.

---
track: T
prio: 60
type: bug
blocked-by: []
summary: "ORACLE_CC lists only ISA-matching cross compilers, while the module's own comment three lines above says the DATA MODEL decides comparability and the ISA does not. A native LP64 gcc is a legitimate oracle for aarch64 and riscv64; because the table does not know it, axis 2 on this box reports NO ORACLE and silently degrades to the weaker pxx-vs-pxx cross-check on the one cross backend Track O actually invests in."
status: done
---

# `ORACLE_CC` is keyed on the ISA; the file's own doctrine says the data model decides

- **Track T** — `tools/csmith_fuzz.py` (the candidate table only; the probe machinery is
  already correct).
- **Found by** Track C (frank2) on 2026-08-20, running axis 2 of
  [[feature-c-csmith-differential-fuzzing]]. Measured, not reasoned — see below.
- **Routed through the coordinator** per that campaign's standing rule: C runs the
  harness, anything inside `tools/csmith_fuzz.py` is T's.

## The contradiction, in the file itself

`tools/csmith_fuzz.py:120` states the doctrine:

> The data model decides whether a checksum is comparable at all; the ISA does not.
> csmith programs are UB-free and deterministic, so two builds of one program agree when
> `long`/pointer widths agree — and disagree, legitimately, when they do not.

`ORACLE_CC`, twelve lines below, then lists **only ISA-matching cross compilers**:
`aarch64-linux-gnu-gcc` for aarch64, `riscv64-linux-gnu-gcc` for riscv64, and so on. A
native x86-64 `gcc` is LP64. So is aarch64. So is riscv64. By the file's own principle it
is a valid oracle for both, and the table does not offer it.

## What it costs right now

**This box has no cross gcc for any non-x86_64 target.** `aarch64-linux-gnu-gcc`,
`arm-linux-gnueabihf-gcc`, `riscv32/64-linux-gnu-gcc`, `i686-linux-gnu-gcc` are all absent,
and `gcc -m32` is precisely the case the probe was written for (accepts the flag, cannot
find `Scrt1.o`, does not link). So the harness reports `NO ORACLE for aarch64 (LP64)`,
drops `MISCOMPILE_VS_GCC`, and axis 2 degrades to the pxx-vs-pxx `-O` cross-check.

**The harness is behaving correctly and saying so out loud** — that is `764e98048`'s "never
report a comparison it did not make" working as designed, and it is why the degradation was
visible at all rather than silently passing as coverage. The defect is upstream of it: the
candidate list is too narrow, so a usable oracle is never offered to the probe.

The cost is concentrated: **aarch64 is the one cross backend Track O actually invests in**,
and it is exactly the target this turns from "no oracle" into a full differential, on this
box, today.

## Evidence

frank2 measured before filing, in a scratch script rather than in T's file: build with
native `gcc -O0`, build with `pascal26 --target=aarch64`, run the latter through
`tools/run_target.sh`, diff the checksums.

**3 agreed, 2 skipped (gcc-side build/run failures), 0 divergences** on the validation
seeds; a 120-seed run was in flight at filing. The premise holds — checksums match across
the ISA boundary.

Sha: self-hosted fixedpoint at `272e347bb`, rebuilt rather than assumed (the tree carried a
comment-only edit on top of the last build).

## The fix

`ORACLE_CC` should fall back to **any probed compiler whose DATA MODEL matches**, not only
one whose ISA matches. `["gcc"]` becomes a legitimate last-resort candidate for aarch64 and
riscv64; `["gcc","-m32"]` for the ILP32 targets on a box that can link it. The probe already
build-and-runs each candidate through `run_target.sh`, so the machinery exists — this is a
candidate-list change plus, ideally, a report line distinguishing a *matched-ISA* oracle
from a *matched-data-model* one so a reader knows which comparison was made.

## CAVEAT — the equivalence is not total, and a false positive here would be filed as a backend bug

Raised by the coordinator, not by the reporter; worth measuring before trusting a first
divergence. Data-model equality covers `long`/pointer width, and every target in `TARGETS`
is little-endian, so the two big axes are handled. What it does **not** cover is anything
where two ABIs legitimately disagree at the same data model — most concretely **bitfield
layout**, where SysV x86-64 and AAPCS aarch64 have genuinely different packing rules, and
where we already have an open finding ([[bug-c-bitfield-packing-sizeof-vs-gcc]]).

If a csmith program's checksum can depend on bitfield placement or struct padding, a
cross-data-model-oracle divergence may be **correct behaviour on both sides** and must not
be filed as a codegen bug. Suggested disposal: on the first divergence from a
matched-data-model (rather than matched-ISA) oracle, reduce far enough to say whether a
bitfield or padding is involved before routing it to Track A. Cheap insurance against the
expensive failure — a wrong root cause recorded in a ticket.

### CORRECTION 2026-08-20 — the caveat also covers the CROSS-BACKEND run, and lands harder there

The coordinator originally scoped this caveat to the external-oracle comparison and told
both Track C and Track T that the ILP32 cross-backend run (i386 / arm32 / riscv32, all
ILP32, our three backends against each other) was exempt because "both sides are ours, so
any disagreement is ours by construction". **That is wrong.** Ours by construction, yes; a
*bug* by construction, no.

i386 is SysV, arm32 is AAPCS32, riscv32 is the riscv psABI, and the three have genuinely
different bitfield and struct-packing rules. **Three backends each correctly implementing
its own ABI can legitimately print different checksums** — a csmith checksum reaches layout
through unions and bitfields even though it only ever hashes values. Removing the external
oracle removes the *"is gcc right?"* dispute; it does not remove the *"is this a legitimate
ABI difference?"* one. With three ABIs in play instead of two, the caveat is **stronger**
here, not absent.

Caught by frank2 before the coordinator's version was acted on. The underlying error was
treating "we own both sides" as equivalent to "any difference is a defect" — **ownership of
the code is not ownership of the specification it implements.**

**Track C built the discriminator into the run rather than leaving it as a reduction chore:**
on any divergence, re-run the SAME seed with `--no-bitfields --no-packed-struct
--no-unions`. Agreement then means layout-dependent — reported `LAYOUT-SUSPECT`, not a
finding. Still disagreeing with all three constructs gone means a real backend disagreement,
and the program is saved. Worth adopting in `tools/csmith_fuzz.py` itself: it converts
"reduce far enough to rule it out" into a one-command classification at the moment of the
hit, and **this campaign's cost has always been reduction, not discovery.**

Note the option deliberately NOT taken: disabling those constructs for the whole sweep.
Bitfields produced three of the first nine bugs in this campaign, so switching them off to
make divergences easier to read would trade the richest territory for convenience. **Run
wide, classify on hit.**

## Gate

T's own lane gate for its tooling.

## 2026-08-20 — THE FIX IS CHEAPER THAN THIS TICKET SAYS: the oracle is already computed and thrown away

Found by frank2 reading `fuzz_one` while the aarch64 batches ran; **verified independently
by the coordinator in the source** rather than relayed, because it changes the fix.

`tools/csmith_fuzz.py:256` builds and runs a **native x86-64 `gcc -O0` on every seed,
unconditionally**, as a *validity filter* — "is this program buildable and runnable at
all". Its checksum is kept in `gcc_out` and its wall time in `gcc_sec`. Then at line 274:

```python
if cfg.target == "x86_64":
    oracle_sum, oracle_sec = gcc_out.strip(), gcc_sec   # it IS the native gcc
else:
    ... build a SECOND binary with the cross compiler ...
```

Native gcc is LP64. So are aarch64 and riscv64. **For an LP64 target the oracle's checksum
is already computed and then discarded**, purely because the guard asks about the ISA
(`target == "x86_64"`) rather than the data model — the same ISA-vs-data-model confusion
this ticket is about, in a second place.

So the fix is **not** "add `["gcc"]` to `ORACLE_CC` and pay for another build". It is:

```python
if TARGETS[cfg.target] == TARGETS["x86_64"]:
    oracle_sum = gcc_out.strip()
```

Zero extra build cost, no new probe, and it lights up `MISCOMPILE_VS_GCC` for aarch64 and
riscv64 immediately. The ILP32 targets still need a real ILP32 compiler, which this box
does not have.

### TRAP — reuse the CHECKSUM, never the TIMING

Coordinator's note, and it is why the one-line version above assigns `oracle_sum` only.
`oracle_sec` scales pxx's budget at line 291: `run_limit = max(floor, TIMEOUT_FACTOR *
oracle_sec)`. The module's own comment at line 267 already states the rule — the oracle
"has to be run the way the pxx binaries are run (same emulation, same runner), or the
ratio the timeout is scaled off measures qemu rather than the compiler."

A native gcc run and an emulated aarch64 pxx run are **not** the same way. Reusing
`gcc_sec` for an emulated target would scale the budget off native silicon while pxx runs
under qemu — an order of magnitude apart — and manufacture `PXX_TIMEOUT` findings out of
programs that are merely emulated. That is the `PXX_SLOW`/hang confusion of
[[bug-t-csmith-harness-reports-slow-as-a-timeout]] returning through a new door, and it
would look like a real finding.

**Correct shape:** take `gcc_out` as the checksum oracle; leave `oracle_sec` `None` for
emulated targets so the budget stays the widened flat floor, and keep reporting the timing
comparison as NOT CHECKED. **Checksum comparability and timing comparability are different
questions with different preconditions** — data model for one, execution environment for
the other. Do not let one flag answer both.

### Also: the skip message names the wrong thing

With no oracle configured, a skipped seed still prints `skip (gcc could not build/run
it)`. That is correct for the validity filter and reads wrong in a run whose banner just
said there is no gcc for this target — the reporter had to read the source to learn whether
the skips meant anything. **Name the validity filter, not "gcc".** Small, and it is the
class of thing that makes a reader distrust a dry run.

## 2026-08-20 — the batches these came from: 270 seeds on aarch64, ZERO findings

Reported as a batch per the campaign's dry-run rule. Self-hosted fixedpoint at `272e347bb`.

- **D1, `--target aarch64`, seeds 300100-300249 (harness as delivered).** 150 seeds: **136
  ran clean across pxx `-O` levels, 14 skipped, no findings.** No `MISCOMPILE_OPT`, so
  `-O0` and `-O2` agree with each other on the aarch64 backend. `MISCOMPILE_VS_GCC` and
  `PXX_SLOW` **NOT CHECKED** — no LP64 oracle under the current table — and the harness
  said so on every report line, which is the behaviour to keep.
- **D2, the LP64 cross-data-model differential, seeds 310100-310219.** 120 seeds: **105
  agreed with native gcc, 15 skipped, 0 divergences.** This is the comparison `ORACLE_CC`
  does not currently offer. Every checksum matched; no reduction needed and the bitfield
  caveat never had to apply.

**270 seeds on aarch64, zero findings, with the strongest available oracle live for 120 of
them.** The aarch64 backend agrees with gcc on random UB-free programs and with itself
across `-O` levels. Read against the campaign's history — 1450 seeds on axis 3 without a
`MISCOMPILE_VS_GCC` — the tail is thin on this backend too. **That is not evidence the axis
was a bad bet: it is the first time any cross backend has seen a random program at all**,
and a first-ever sweep coming back clean is a result worth the same paragraph a finding
would get.

## CORRECTION 2026-08-20 — the fix buys ONE target, not two

The line above ("lights up `MISCOMPILE_VS_GCC` for aarch64 and riscv64 immediately")
is wrong on the second target. **It buys exactly aarch64.**

Caught by frank2, verified in source by both sides rather than relayed:
`compiler/defs.inc` defines `TARGET_I386=1`, `TARGET_AARCH64=2`, `TARGET_ARM32=3`,
`TARGET_XTENSA=4`, `TARGET_RISCV32=5` — **there is no `TARGET_RISCV64`**, and `riscv64`
occurs nowhere in `compiler/**`. So there is nothing on the pxx side of the comparison
to light up: `--target riscv64` fails at the pxx invocation, upstream of any oracle.

`riscv64: "LP64"` stays in `TARGETS` and its `ORACLE_CC` row stays too — the table is
**correct-in-advance**, not wrong, and it needs no edit the day the backend lands. What
was missing was a reader being able to tell those two states apart, so both rows now
carry a comment saying pxx has no riscv64 backend yet. **A target list is not a backend
list**, and this ticket briefly read as if it were.

## 2026-08-20 — the fix, measured: 160 cross-target comparisons on aarch64, ZERO divergences

Run by Track C (frank2) with the one-line fix live. Self-hosted fixedpoint at `21f05c52b`,
`tools/csmith_fuzz.py` at `174186b5d`.

**160 real checksum comparisons against the native `gcc -O0` oracle, 0 divergences** —
the strongest class of evidence this campaign has produced, because it is the first time
a cross backend has been checked against an *external* implementation rather than against
another build of itself.

The header line is the visible proof the fix took, and it is exactly the "never report a
comparison it did not make" discipline moving from a refusal to a claim:

| before | after |
| --- | --- |
| `NO ORACLE for aarch64 (LP64)` | `vs gcc -O0 oracle (datamodel)` |
| `MISCOMPILE_VS_GCC and PXX_SLOW are NOT CHECKED this run` | `Checksums are compared; TIMING is not` |

The second row is the TRAP section above holding: the checksum is reused, `oracle_sec` is
not, so `PXX_SLOW` stays honestly unchecked on an emulated target instead of manufacturing
timeouts out of qemu. **Checksum comparability and timing comparability really are
different questions, and the report now answers them separately.**

## Log
- 2026-08-20 — resolved, commit 350e093ff.

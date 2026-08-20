---
track: T
prio: 60
type: bug
blocked-by: []
summary: "ORACLE_CC lists only ISA-matching cross compilers, while the module's own comment three lines above says the DATA MODEL decides comparability and the ISA does not. A native LP64 gcc is a legitimate oracle for aarch64 and riscv64; because the table does not know it, axis 2 on this box reports NO ORACLE and silently degrades to the weaker pxx-vs-pxx cross-check on the one cross backend Track O actually invests in."
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

## Gate

T's own lane gate for its tooling.

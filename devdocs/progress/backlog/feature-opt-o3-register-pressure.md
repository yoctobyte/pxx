---
prio: 58  # auto — greenlit optimization campaign; real speed win but exploratory, behind -O3
---

# -O3 register-pressure tier: operand scheduler + liveness-scaffold register allocator

- **Type:** feature (codegen — optimization) — **Track A** — umbrella for the
  next optimization campaign.
- **Status:** backlog — greenlit 2026-07-10. Exploratory work lands **behind
  `-O3`** (see gating); `-O2` stays the proven default and the stable fallback.
- **Opened:** 2026-07-10 (post -O2-default flip, [[feature-optimization-levels]]).
- **Owner:** —

## Why — the measured opportunity

The compiler is a single-pass stack machine, so most emitted work is moving
values, not computing them. Measured on a real build (O2 compiler self-compiling
`compiler.pas`, **937k emitted instructions**):

| category | share | what it is |
|---|---|---|
| push/pop | **22.6%** | per-statement operand staging (`push rax; eval right; pop rcx`) |
| rbp loads | 9.4% | reload local/param from frame |
| rbp stores | 5.0% | spill to frame |
| **frame traffic total** | **37%** | memory shuffling, NOT compute |
| calls | 12.3% | |

r14/r15 param residency ([[feature-callconv-register-args]]) already bought
**1.34× self-compile from just 2 registers** — direct proof the lever is real and
far from exhausted. Killing the 37% is where the next multiplier lives.

## Pipeline home — decided (do NOT post-rewrite bytes)

Register work lives **before bytes, over the IR** — a *planning* pass that
annotates, then the emitter reads the annotation and emits once. NOT a
post-emission byte peephole.

- Hard rule: **no pass rewrites emitted bytes** — branch/label fixups store
  absolute `CodeLen` offsets. (A post-byte pass is not *impossible* — fixups are
  already tracked lists and could be re-based when bytes move — but x86
  variable-length encoding + 6 backends make it strictly more machinery than
  planning up front, for no extra reach.)
- Allocation is fundamentally **global**: "keep `x` in r13" needs `x`'s whole
  live range and every contender for r13. Can't be a local/post decision.
- **Plan over the IR with live-range data, never reserve registers blind.**
  Reserving before you know contention is exactly how the residency re-emit bug
  happened ([[project_regcall_residency_reemit_localinit_clobber]]).

The data splits the work cleanly by home:
- **push/pop (22.6%) → emit-time operand scheduler** (local, no scaffold).
- **rbp load/store (14%) → planning-phase register allocator** (global, needs
  liveness).

## Workstreams (suggested order)

### W1 — emit-time operand scheduler (do first; best effort:payoff)
Kill the binop `push rax; eval; pop rcx` dance without any liveness analysis.
Peepholes 1–2 already direct-load *leaf* operands into rcx; generalize to a
small per-statement register scheduler over expression trees (rax/rcx/rdx +
caller-saved r8–r11 are free *within* a statement, clobbered only across calls).
Local, low-risk, attacks the single biggest slice. De-risks the register model
before the bigger scaffold. x86-64 emitter (§3b); a cross variant later.

### W2 — register-liveness scaffold → linear-scan allocator (the keystone)
A pre-emit IR pass computing per-body live ranges, then assigning free
callee-saved + caller-saved registers to the longest-lived / hottest values,
annotating the IR/symtab (generalize the `RcResident*` mechanism the emitter
already reads). Kills the 14% frame load/store. **Unblocks two queued items that
share exactly this scaffold:**
- [[feature-opt-store-reload-elimination]] (blocked on it today)
- [[feature-callconv-register-args]] phase 2 (rbx/r12/r13) + hot *locals*, not
  just params.

Highest effort, highest ceiling. Estimate another ~1.3–1.5× on top of current,
compounding with W1.

### W3 — ride-alongs (cheap, after the scaffold exists)
- regcall phase 2/3 on the new liveness data.
- store-reload elimination.
- relocate compare-fusion (peephole 4) to an IR tag → cross targets get it.

## Out of scope (captured so it is not lost)
**Code-block reordering for locality** ("code that runs together lives in the
same/nearby page"). Genuinely useful, but needs **profile / runtime hotness
data** to know which blocks co-run — the compiler has no PGO input, so this is
out of scope until there is a profiling story. Note it here; do not attempt
blind.

## Gating & fallback (the whole point of -O3)
- All in-flight work gates **`OptLevel >= 3`**. `-O3` currently just aliases
  `-O2` (nothing gates `>=3`), so it is a free experimental tier: passes fire
  only at `-O3`, and the `-O2` default stays byte-for-byte what it is today = the
  stable fallback every track builds on.
- Per pass, promote `-O3 → -O2` **only after the full gate**, the same bar slice
  2b cleared: 500-program `-O0`-vs differential byte-clean, all four cross
  targets (i386/aarch64/arm32/riscv32), `-O2` self-host fixedpoint byte-identical,
  `make test` + `make test-opt` green. Land only green; never a long-lived branch.
- `-O0` remains the byte-identity reference and is never touched (passes gate
  `OptLevel >= tier`).

## Acceptance (umbrella — each pass is its own landed unit)
- W1 shipped at `-O3`, measurable push/pop reduction, promotable to `-O2` under
  the gate above.
- W2 scaffold exists and at least one consumer (allocator OR store-reload-elim)
  ships at `-O3`.
- Net self-compile speedup measured and recorded; the 37% frame-traffic figure
  meaningfully reduced.

## Links
Umbrella [[feature-optimization-levels]] · [[feature-opt-store-reload-elimination]]
· [[feature-callconv-register-args]] · [[feature-inline-nonleaf-and-branch-locals]]
· lesson [[project_regcall_residency_reemit_localinit_clobber]] ·
architecture `devdocs/dev/optimization-architecture.md`.

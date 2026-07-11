---
prio: 58  # auto — greenlit optimization campaign; real speed win but exploratory, behind -O3
---

# -O3 register-pressure tier: operand scheduler + liveness-scaffold register allocator

- **Type:** feature (codegen — optimization) — **Track O** (Optimization lane;
  file-ownership **Track A** — edits the shared `ir_codegen.inc` / `symtab.inc` /
  backends, so it obeys A's no-concurrent-edit rule + self-host gate) — umbrella
  for the next optimization campaign.
- **Status:** working
  `-O3`** (see gating); `-O2` stays the proven default and the stable fallback.
- **Opened:** 2026-07-10 (post -O2-default flip, [[feature-optimization-levels]]).
- **Owner:** fable-O

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

## Target scope — per-backend effort = x86-64 + aarch64 only
Optimization splits by home (see `optimization-architecture.md` §3): **shared-IR
passes (§3a) help all six targets for free** — one implementation, keep those
target-agnostic. **Per-backend work (§3b: emitter peepholes, the operand
scheduler, the register allocator's emit side) targets x86-64 + aarch64 ONLY.**
Rationale:
- **32-bit (i386 / arm32 / riscv32): perf-irrelevant.** Legacy / control-plane /
  bring-up correctness, never throughput. Not worth per-backend allocator effort.
- **ESP32 / xtensa: special case, also skip.** Its perf-critical paths are the
  hardware peripherals (DMA / ADC / SPI capture), already supported and offloaded
  to silicon — not compiled-code throughput. Tight compiled loops there are rare
  and not the bottleneck.
So: build W1/W2 for x86-64 first, aarch64 second; do NOT port the register
allocator to the 32-bit or xtensa backends. Shared-IR passes (DCE, any future
IR-level transform) still land once and benefit all — no reason to gate those.

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

**Leaf functions first (the golden class).** A function that calls nothing
(`ProcBodyMakesCall = false`, already computed by the inline pass) may use all 9
caller-saved registers (rax,rcx,rdx,rsi,rdi,r8–r11) as scratch with **zero
save/restore** — nothing can clobber them. Simplest, highest-value case: no
prologue register save, whole scratch set free. Start the scheduler here, extend
to non-leaf (where cross-call values need callee-saved or spill) after.

**Standard ABI preserved at every call boundary.** W1/W2 do *internal* allocation
only — callers never see it, so nothing crystallizes and each body is an
independent island. Custom register *calling conventions* (caller-side param
passing, which DOES crystallize into the callee's ABI and only works when every
call site is direct+visible — breaks on fn-pointers / virtual / exported /
separate compilation) are explicitly **deferred** to a regcall-phase-3 follow-up
([[feature-callconv-register-args]]), not part of W1/W2.

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

## Log

### 2026-07-11 — W1 slice 1 LANDED behind -O3 (x86-64): binop mirror + r8/r9 scratch + leaf-index fold
- **What fires** (all gate `OptLevel >= 3`, x86-64 emitter only, `not InLValueWrite`):
  1. **Mirror**: leaf LEFT binop operand (const / plain scalar sym) loads AFTER
     the complex right evaluates — kills push/eval/mov/pop from the left side.
     Const left reorders across anything (incl. calls); sym left requires a
     proven side-effect-free right.
  2. **Scratch**: complex-complex binop parks the left value in r8 (nested: r9;
     deeper: push/pop fallback) across the right's evaluation when
     `ScratchSafeSubtree` proves the right subtree call-free and r8/r9-clean.
     Whitelist predicate in symtab.inc next to LeafSymRcxLoadable; notable
     exclusions documented there (tkIn uses r8; string concat/cmp call helpers
     or inline through r8/r10/r11).
  3. Both also applied to the compare-into-branch fusion operand dance.
  4. **Leaf-index fold** (IR_INDEX): const index → single `add rax, disp`
     (nothing for elem 0); leaf-sym index → load/scale in rcx directly. Kills
     the push-base/eval-index/pop-rcx dance on every simple array access.
- **Measured** (self-compile of compiler.pas, -S instruction mix O2 → O3):
  total instructions 940,900 → 873,386 (**−7.2%**); `pop rcx` 34,374 → 14,175;
  `pop rax` 20,690 → 16,749; `push rax` 99,877 → 75,757; emitted code
  4,160,828 → 4,031,287 B (**−3.1%**). Wall-clock: 3.406s → 3.356s
  (~1.5%, hyperfine ±0.02 — OoO/stack-engine hides most of the stack-op win,
  consistent with the regcall-phase-2 lesson).
- **Gates run**: -O2 self-host fixedpoint byte-identical (untouched, pass
  inert below -O3); -O3 self-host fixedpoint byte-identical; -O3-built
  compiler's -O2 output byte-identical to the -O2-built compiler's; test-opt
  extended with an -O3 differential column + -O3 fixedpoint (green).
- **Remaining W1 targets** (instruction-mix census at -O3): `pop rdi` ~31k +
  `pop rsi` ~10k = runtime-helper ARG staging (hand-coded per call site);
  `pop rax` 16.7k = binop dances whose right subtree contains calls — needs a
  callee-saved scratch (r12/r13 + prologue/epilogue save) = the W2 boundary.

### 2026-07-11 — W1 slice 2 LANDED behind -O3: callee-saved r12/r13 scratch across call-bearing right subtrees
- The remaining generic binop dances (right subtree contains calls, so r8-r11
  die) now park the left value in **r12/r13**, which survive calls. Per main
  body, `CalleeScratchAssign` (called from CompileAST after IROptimize, under
  the same suppression discipline as regcall residency) pre-scans the final IR;
  if any BINOP/fused-compare right operand would take the push/pop path, it
  reserves two frame slots, saves caller r12/r13 once at entry, and
  `EmitProcEpilog` restores them on every return (mirrors the r14/r15 restore).
  Bodies with inline asm bail entirely (user asm may use r12/r13 across
  statements); value subtrees cannot contain IR_ASM (asm is statement-only),
  and every runtime path (pxx bodies, helper blobs, CoSwitch context save, the
  setjmp buf) preserves r12/r13 — audited before landing.
- **Measured runtime of compiled programs, -O2 vs -O3 (identical outputs):**
  mandelbrot --bench **1.14×** (86.7→76.3 ms), raytracer 1.04×, sieve 1.01×
  (memory-bound), compiler self-compile 1.01× (memory-bound — IPC rises but
  the frontend is cache-limited, consistent with the label-clear findings).
  W1's payoff is compute-bound user code, not the compiler itself.
- Fire: `mov r12, rax` ×1802 in the self-compile image; binop pop-dances
  20.7k (O2) → 14.9k (O3 incl. slice 1).
- Gates: -O2 fixedpoint untouched + byte-identical; -O3 self-host fixedpoint
  byte-identical; test-opt (incl. -O3 column + fixedpoint) green; make test
  green; testmgr quick GREEN.

### 2026-07-11 — W2 slice 1 LANDED behind -O3: loop-local register residency (r12/r13)
- `LoopResidencyAssign` (CompileAST, after IROptimize): tallies LOAD/STORE_SYM
  accesses inside backward-jump loop ranges (nested ranges credit twice —
  natural depth weighting), picks up to two eligible scalar locals/params
  (>3 loop accesses, no addr-taken, RegcallScalarType) and keeps them resident
  in r12/r13 — the r14/r15 regcall mechanism generalized (choke-point encodings
  now computed from the register number; residency arrays widened to 4). Body
  entry saves the caller's r12/r13 to frame slots; every store dual-writes +
  refreshes; the epilogue and the IR_EXC_ENTER exception-landing refresh cover
  all exits (the longjmp-rollback landmine fixed earlier today). Mid-body
  IR_ZERO_SYM on a resident local now refreshes too. Mutually exclusive per
  body with the W1 r12/r13 callee scratch (residency wins; scratch bails).
- **Why this works when regcall phase-2 (more param residency) was rejected:**
  the target is the LOOP-CARRIED store-forward chain through the frame slot
  (i := i + 1), which OoO cannot hide — not plain L1 reloads, which it can.
- **Measured (-O2 vs -O3, outputs identical):** compiler self-compile
  3.427 → 3.268 s = **1.05×** (was 1.01× with W1 alone); sieve 1.03×;
  mandelbrot stays 1.13× (its loop kernel is float — excluded from residency,
  wins came from W1). Cumulative -O3 story: compute-bound 1.13×, self-compile
  1.05×.
- Gates: -O2/-O3 self-host fixedpoints byte-identical; test-opt (incl. -O3
  differential + fixedpoint) green; make test green; quick GREEN.

### 2026-07-11 — W2 slice 2 LANDED behind -O3: float loop residency in xmm8/xmm9
- Up to two loop-hot **tyDouble** locals/params stay resident in xmm8/xmm9 for
  the whole body. xmm8-15 are caller-saved, so there is NO save/restore and no
  exception/longjmp interplay — the trade is that residency is legal only in
  bodies whose entire IR emission is provably call-free
  (`FloatResidencyBodySafe`: node-kind whitelist + no managed-string /
  dyn-array store traffic; div/mod allowed since the div-zero call never
  returns). tySingle is excluded on purpose: a register cache would hold the
  unrounded double and diverge from the frame's narrow-then-widen roundtrip.
- Reads: `movaps xmm0, xmm8/9` in EmitLoadVar's float path; stores dual-write
  (`movaps xmm8/9, xmm0` after the frame write); IR_ZERO_SYM refreshes.
- **Measured (-O2 vs -O3, outputs identical):** mandelbrot --bench **1.21×**
  (83.7 → 69.4 ms; was 1.13× before this slice), raytracer 1.04× (its kernels
  call Vec helpers → bodies not call-free; inline-expansion follow-up would
  unlock it). Cumulative -O3: mandelbrot 1.21×, self-compile 1.05×.
- Gates: -O2/-O3 fixedpoints byte-identical, test-opt green, make test green,
  quick GREEN.

### 2026-07-11 — W1 slice 3 LANDED behind -O3: last-call-argument push/pop collapse
- Internal (non-variadic, <=6-param) calls push every arg then pop them into
  the SysV registers; the LAST argument's push/pop pair is back-to-back — it
  now stays in rax and takes a single `mov <its reg>, rax` (nothing between
  the last eval and the pop loop touches rax; the hidden aggregate-dest eval
  runs after the pops). Variadic and >6-param stack-convention calls
  unchanged.
- **Measured:** self-compile image `pop rdi` 31.1k → 9.4k, `push rax`
  75.8k → 44.9k, total instructions 890.8k → 860.5k (**−8.5% vs -O2**
  cumulative). Runtime: raytracer 1.04× → **1.09×** (call-heavy code),
  mandelbrot holds 1.20×, self-compile 1.04-1.05×.
- Gates: -O2/-O3 fixedpoints byte-identical, test-opt green, make test green,
  quick GREEN.

### 2026-07-11 — W1 slice 3b: last-arg collapse extended to virtual + indirect calls
- Same transform as the direct-call collapse, applied to IR_VIRTUAL_CALL
  (register-convention dispatch, <=6 params) and IR_CALL_IND's internal path.
  cdecl indirect calls and the >6-param stack conventions unchanged. Matters
  for OO/method-pointer-heavy user code rather than the compiler itself.
- Gates: -O2/-O3 fixedpoints byte-identical, test-opt green, make test green,
  quick GREEN.

## Next steps (queued, in rough order)
1. **Record-aware inline** (the raytracer unlock): Vec3-style record
   params/returns block both inline v1 (scalar-only) and float xmm residency
   (helper calls make bodies non-call-free). SROA-like splitting of small
   by-value records into scalars at inline sites — multi-session effort, file
   under [[feature-inline-routines]].
2. **-O2 promotion** of the W1/W2 set after soak: the ticket's full gate
   (500-program -O0-vs differential, all four cross targets, -O2 flip +
   re-pin). Hold until T is back up or run the matrix locally.
3. IR_INDEX callee-scratch for call-bearing index expressions (rare; cheap
   once measured worthwhile). Remaining stack-op census after slice 3b:
   pop rdi 9.4k (cdecl/variadic staging), pop rax 14.9k (call-y binop
   dances at depth>2 / InLValueWrite contexts), pop rcx 14.2k (complex
   index/base dances).

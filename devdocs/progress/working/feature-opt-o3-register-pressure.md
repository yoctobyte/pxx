---
prio: 85
---

# -O3 register-pressure tier: operand scheduler + liveness-scaffold register allocator

- **Type:** feature (codegen — optimization) — **Track O** (Optimization lane;
  file-ownership **Track A** — edits the shared `ir_codegen.inc` / `symtab.inc` /
  backends, so it obeys A's no-concurrent-edit rule + self-host gate) — umbrella
  for the next optimization campaign.
- **Status:** working
  `-O3` (see the 2026-08-26 log at the bottom: **1.29x on the self-compile**,
  gap to fpc 4.06x -> 3.24x). Nothing is half-applied; every commit passed the
  `-O3` self-host fixedpoint and `gate.sh quick`. Parked because the umbrella's
  core — W2, a real register allocator — is a multi-session project, and the
  measurements plus the next slice are now banked below.
  **Two things wait on someone else:** the `-O2` promotion of the four `-O3`
  passes (coordinator's call — that is where most of the 1.29x still sits), and
  Track T's sweep of `e7c0d1d2a`.
  New passes still land behind **`-O3`** (see gating); `-O2` stays the proven
  default and the stable fallback.
- **Opened:** 2026-07-10 (post -O2-default flip, [[feature-optimization-levels]]).
- **Owner:** frankA

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

### 2026-07-11 — PROMOTED to -O2: mirror + leaf-index fold + last-arg collapse
- The three mechanically-local W1 passes (no register-lifetime state) moved
  from -O3 to the -O2 default after the promotion gate: **564-program corpus
  -O0-vs-O2 differential clean** (4 flagged = harness noise: gtk pointer
  output nondeterministic at -O0 too; lib_sockets port TIME_WAIT flake,
  hangs identically at both levels), -O2/-O3 self-host fixedpoints
  byte-identical, test-opt, make test, quick GREEN. Compiler reseeded
  (2-step build can't converge across a codegen change).
- Promoted-set effect at the new default: raytracer **1.07×**, self-compile
  ~1.03×; mandelbrot ~1.01× (its wins live in the register passes).
- **Still -O3-only** (register-lifetime schemes, need soak): r8/r9 scratch,
  r12/r13 callee scratch, loop-local residency, float xmm residency —
  worth another promotion pass after a few days of -O3 soak + T back up.

---

## Measurement, 2026-08-26 (agent-A-perf-9s) — the gap has a number now: **~4x FPC**

Found while resolving `bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost`.
That ticket's four fixes removed the algorithmic hotspots from the compiler's
own hot path (8.62s -> 4.06s on a NilPy compile). What is left is **not**
algorithmic, and this ticket is where it lives.

**The end-to-end number.** `compiler.pas` built by `fpc -O2` and `compiler.pas`
built by pxx `-O2` are the same source and emit byte-identical output. Compiling
`empty.npy`:

| compiler binary | wall |
| --- | --- |
| built by `fpc -O2` | **1.06s** |
| built by pxx `-O2` (self-hosted, sha 66c9b8332) | **4.06s** |

Same work, same output, **3.8x**. Every self-host, every test binary, every
compile every agent runs, carries that factor.

**Isolated, so it is not an artifact of one workload.** Three locals, no memory
traffic, no arrays, no strings, no bounds checks in play:

```pascal
program b_loop;
var i, s, t: Integer;
begin
  s := 0; t := 1;
  for i := 1 to 200000000 do begin s := s + i; t := t xor s; end;
  WriteLn(s, ' ', t);
end.
```

| build | wall |
| --- | --- |
| pxx `-O2` | 0.78s |
| pxx `-O3` | 0.77s |
| `fpc -O2` | **0.19s** |

**4.1x, and `-O3` does not move it.** Both print the identical result, so this
is a codegen comparison and not a semantics difference. A second benchmark
(1000-element array fill + sum, 20k iterations) gives 0.16s vs 0.04s, the same
ratio; a string-append benchmark gives 0.42s vs 0.24s, i.e. **the RTL is not the
problem — scalar code is.**

**`-S` says exactly what is wrong.** The whole emitted loop body, pxx `-O2`:

```
loop:
    movsxd rax, [0x0041a7f0]     ; load i
    mov    rcx, 0x0bebc200       ; rematerialise the loop bound
    cmp    rax, rcx
    jg     exit
    movsxd rax, [0x0041a7f4]     ; load s
    movsxd rcx, [0x0041a7f0]     ; load i  (2nd time)
    add    rax, rcx
    mov    [0x0041a7f4], eax     ; store s
    movsxd rax, [0x0041a7f8]     ; load t
    movsxd rcx, [0x0041a7f4]     ; load s  (just stored, one instruction ago)
    xor    rax, rcx
    mov    [0x0041a7f8], eax     ; store t
    movsxd rax, [0x0041a7f0]     ; load i  (3rd time)
    mov    rcx, 0x0bebc200       ; rematerialise the bound again
    cmp    rax, rcx
    je     exit
    movsxd rax, [0x0041a7f0]     ; load i  (4th time)
    add    rax, 0x00000001
    mov    [0x0041a7f0], eax
    jmp    loop
```

Twenty instructions and nine memory accesses for what is five instructions and
zero memory accesses of real work. The induction variable is loaded **four times
per iteration**, the loop bound is materialised into a register **twice per
iteration**, and `s` is stored and immediately reloaded. This is the
"single-pass stack machine moves values rather than computing them" cost this
ticket already names, quantified: **~4x, on the simplest possible loop.**

### Why the prio should be revisited (a Track U / coordinator call, not mine)

Sitting at **35**. The owner's loudest standing complaint is *"we see testing
overhead taking 95% of our development time"*, and this is now the **largest
single remaining lever on it** — larger than any tiering or sharding proposal,
and like the ticket it came from it **costs no coverage at all**: the same tests,
faster. `make compiler/pascal26` is 23.4s today and is mandatory in every
agent's per-fix loop on every track; a 2x codegen improvement takes it to ~12s
and takes every test binary with it.

Recorded here rather than acted on: the fix is a register allocator, which is
this ticket's whole subject and a campaign, not a session. Reproduce the two
benchmarks above before starting — they are 30 seconds each and they are the
scoreboard.


## Re-prioritised 35 -> 85 by the coordinator, 2026-08-26

The Track A worker that measured the 3.8x gap flagged this field as a decision
rather than an engineering call and correctly left it alone. Raising it.

**The number is what changed, not the opinion.** The same source built by
`fpc -O2` compiles `empty.npy` in 1.06s against our own `-O2` build's 4.06s,
producing byte-identical output -- so this is not a semantics question, it is
purely how well we allocate registers. Isolated to scalar codegen: a three-local
loop runs 0.78s under pxx at both `-O2` and `-O3` versus 0.19s under fpc, and the
`-S` dump above shows the induction variable loaded four times per iteration, the
loop bound rematerialised twice, and `s` stored then reloaded one instruction
later.

**Why 85 and not higher:** it sits below live segfaults and wrong-value bugs,
which remain the owner's stated top rank (*"compiler syntax, segfaults, etc, all
prio"*). It sits above essentially everything else because it is now the largest
single lever on the owner's other standing complaint -- *"we see testing overhead
taking 95% of our development time"* -- and unlike tiering, sharding or dropping
jobs it **costs no coverage at all**. Every lane pays this tax on every
`make compiler/pascal26`, which is mandatory in every agent's per-fix loop.

The hotspot work that produced this measurement already took `empty.npy` from
8.62s to 4.06s and `make compiler/pascal26` from 32.08s to 23.36s. That was the
easy half. This is the remaining 3.8x, and it is the reason the prio field no
longer matched the value.

---

## 2026-08-26 (agent-O-regalloc) — four passes landed at -O3; **1.29x on the self-compile**, and the ticket's own headline is now measured to be the SMALLER half

Claimed at prio 85 with the brief "the remaining 3.8x is register allocation".
**It is about half register allocation.** The first thing done was to profile
rather than to trust the ticket, and the profile named three misses the ticket
does not mention, each larger than anything the register allocator would have
bought in the same time.

### The instrument (reusable — `bench-o/`, not committed)

`perf` is blocked on plexus (`perf_event_paranoid = 4`) and yama
`ptrace_scope = 1` forbids attaching to a non-descendant, so gdb cannot attach
either. **`tools/pxxprof.c`** (60 lines, committed) solves both: it forks the
target itself, `PTRACE_SEIZE`s its own child, and samples RIP with
`PTRACE_INTERRUPT` on a timer. It profiles any binary including pxx's own
custom-ELF output; **`tools/pxxprof_symbolize.py`** resolves addresses against a
symbol map, which for a pxx binary comes from `-g`'s DWARF `DW_TAG_subprogram`
low_pcs (both headers carry the recipes).
**Two traps recorded so we do not re-learn them:**
- FPC's `-pg` + gprof gives usable **call counts** and useless **times** here
  (three samples for 1.03 s of user time). Read the counts, not the percentages
  — which is exactly what the debugging playbook already says.
- The profiler's own samples land in the **vDSO** at a rate that swings 8% -> 38%
  between runs of the same binary. Exclude out-of-`.text` samples; do not read
  them as time.

Wall-clock discipline: the box also runs Track T's watcher (load 4-15 during
this session), so every timing below is `%U` user time, **A/B alternating**,
reported as the **minimum** of N — the least noise-contaminated estimator.
An A/B harness doing exactly that is three lines of shell; it was scratch, not committed.

### What the profile actually said

Compiler compiling a **one-line** NilPy file, compiler built at `-O2`, sha
`e7f6312d9`. 56% of the run was inside the first 5 KB of `.text` — the runtime
blobs and the builtin heap — and the individual hot instructions were:

| what | share | why |
| --- | --- | --- |
| two `idiv`s in `PXXAlloc` | 8.7% | `((size + 7) div 8) * 8` and `Integer(size div 8) - 1` — **divisor is the literal 8** |
| a third `idiv` in `PXXFree` | 3.5% | same shape |
| the `AnsiStrRelease` blob's push/pop wall | ~11% | ten stack ops to guard a decrement |
| `AsmText*` + `EmitAsmX64` | ~12% | the mini-assembler re-lexing fixed strings — filed separately |

None of that is register allocation. `x div 8` was emitting a real 25-40 cycle
`idiv`, preceded by a zero-check on a constant that is provably non-zero.
`Integer(x)` was emitting **six instructions and 39 bytes** (three of its
constants do not fit a sign-extended imm32, so each became a 10-byte `movabs`)
where `movsxd rax, eax` is three bytes.

### Landed (all `-O3`-gated except where noted)

| sha | pass |
| --- | --- |
| `e9317428d` | **div/mod by a constant power of two** -> shifts and masks. Signed forms bias with `sar 63; shr 64-k` first (Pascal's `div` truncates toward zero; a bare `sar` floors). A non-zero constant divisor also drops the pre-divide zero check — dead code at every such site, `div 10` in every number formatter included. |
| `029f79b26` | **`AnsiStrRelease` blob fast path** (ALL opt levels — a runtime stub, not a pass): only `rax` is saved, and only across the free. Four of the five registers it used to push were being saved a SECOND time by `EmitHeapFreeLocked` on the only path that can clobber them. **+ `-O3` cmp-immediate** in the compare-into-branch fusion. |
| `f9d9da4b5` | **narrowing ordinal cast -> one `movsx`/`movzx`.** `NarrowCastFold` recognises the mask (`movzx`) and the mask/xor/sub triple (`movsx`) the IR lowering spells out, for 1/2/4-byte widths. Value-identical, so a hand-written `x and $FF` folds too. |
| `6692d08b8` | **cmp-immediate for the VALUE-producing compare.** The branch form left the bigger half on the table: a short-circuit `and`/`or` lowers each operand to a boolean VALUE, so `if (c >= 'A') and (c <= 'Z')` still paid `mov rcx, imm32` twice per character — CaseEqual's inner loop, 3.2% on its own. `CmpFusible` moved above `IREmitNode` rather than being restated. |
| `e7c0d1d2a` | **residency refresh reads `rax`, not the slot it just wrote.** This one IS the ticket's subject: the `-O3` residency pass exists to break the loop-carried store-forward chain through a frame slot, and **its own refresh was re-creating one** — every store to a resident emitted `mov [rbp+off], eax; movsxd rax, [rbp+off]; mov r12, rax`. Re-extending `rax`'s low bytes is the same value by construction. `IR_ZERO_SYM` and the `IR_EXC_ENTER` landing pad keep the reloading form on purpose: there the slot, not `rax`, is the authority. |

### Numbers

Same source built by each compiler; baseline binary self-hosted from
`e7f6312d9`, final from `e7c0d1d2a`; plexus, watcher running, min of N.

| workload | base `-O2` (today's default) | base `-O3` | **new `-O3`** | fpc `-O2` |
| --- | --- | --- | --- | --- |
| compile `empty.npy` | 3.65 s | 4.40 s | **2.91 s** | 0.90 s |
| self-compile `compiler.pas` | 18.03 s | — | **13.96 s** | — |

- **`-O3` codegen alone: 1.25x** on `empty.npy` (base `-O3` -> new `-O3`).
- **1.29x on the self-compile** — `make compiler/pascal26`'s own workload, the
  one every agent pays on every fix, on every track.
- **The gap to fpc went 4.06x -> 3.24x**; 27% of it is closed.
- Compiler binary at `-O3`: 9,321,568 -> 9,161,656 bytes (**-1.7%**).
- At today's `-O2` default only the release-blob change is live: **1.018x**.
  Everything else is waiting on the promotion below.

Note the `-O3` baseline is *slower* than the `-O2` baseline (4.40 vs 3.65) —
the register-residency passes were a net LOSS on this workload before
`e7c0d1d2a`, which is what the refresh-reload bug was doing.

### Correctness

Where output changes, byte-identity of the emitted code is not available, so:
- **differentials against two oracles** — `-O0/-O1/-O2/-O3` must agree with each
  other AND with `fpc -O2` on the same source. ~153M div/mod evaluations
  (k = 0..31, div and mod, Int64/Integer/UInt64/Cardinal, dense -300k..300k plus
  a sparse wide sweep and the type extremes); ~134M comparisons (140k values x 4
  types x 20 constants including the imm32 sign-extension boundaries x 6
  operators x branch and value forms); every narrowing ordinal cast plus the
  hand-written idioms **and four deliberate near-misses that must NOT fold**; a
  residency stress whose every store overflows its declared type (so a missing
  re-extension shows at once) including a try/except that stores to residents
  inside the protected block; a string-churn program under `--threadsafe` with
  max RSS as a leak canary. The generators were scratch (`bench-o/`, not committed) — they are a page of Python each and the shapes are described above, which is what a re-run needs.
- `-O3` **self-host fixedpoint byte-identical** after every commit.
- The `-O3`-built compiler's `-O2` output **byte-identical** to the `-O2`-built
  compiler's.
- All four compilers emit **byte-identical output for `empty.npy`**.
- `tools/gate.sh quick` GREEN after every commit (5 runs).

### The one decision left: `-O2` promotion (COORDINATOR / Track U)

All four codegen passes gate `OptLevel >= 3`, so **today's default `-O2` gets
1.018x of the 1.29x**. Promotion needs this ticket's stated bar (500-program
`-O0`-vs differential, four cross targets, `-O2` fixedpoint, `make test` +
`make test-opt`) — breadth this lane may not run. Recommendation: **promote all
four**, because they are in the mechanically-local class the July slice already
promoted (no register-lifetime state, no reordering), except the residency
refresh which touches only a mechanism that does not exist below `-O3`. Each is
backed by a two-oracle differential in the tens of millions of cases. Handing
the call to the coordinator with the sha; Track T's sweep of `e7c0d1d2a` is the
evidence path.

### Next slice, in priority order (measured, not guessed)

1. **The three-local loop is still 3x off fpc** — `0.65 s` vs `0.22 s` at `-O3`
   (was 0.76). What remains is exactly W2: only ONE of the three locals gets a
   register (the eligibility threshold is *>3 loop accesses*, which excludes the
   accumulator `s` at exactly 3), and the other two live in the frame across the
   whole loop. Two cheap experiments before building anything bigger: **lower the
   threshold**, and **use all four free callee-saved registers** rather than two.
   A `for`-loop induction variable should also be resident unconditionally.
2. **Globals are not residency candidates at all** — the ticket's own headline
   `-S` dump uses program-level `var`s, which is why `-O3` "bought nothing" on
   it. A global with no address taken and no call in the loop body is as
   register-able as a local.
3. **The boolean temp** the short-circuit `and`/`or` lowering materialises:
   `setae al; movzx rax, al; mov [rbp-31], al; movzx rax, [rbp-31]; test rax, rax`
   — a frame round-trip per condition operand, four per CaseEqual iteration. The
   `-O3` store->reload eliminator already handles the non-resident case; a
   resident destination is explicitly excluded by `ReloadElimSym`, and that
   exclusion's stated reason (the refresh clobbers rax via a reload) **is no
   longer true after `e7c0d1d2a`**. Revisit it.
4. **`EmitAsmX64` re-lexes fixed strings** — ~12% of a NilPy compile, filed as
   [[feature-opt-emitasmx64-reparses-fixed-strings]] (Track A+O, prio 60). Not
   codegen; a different file set; kept out of this ticket deliberately.
5. Non-power-of-two constant divisors via magic-number reciprocals (`div 10` is
   in every number formatter). Cheap once someone wants it.

### One thing to keep in mind when touching `IR_BINOP`

Three of these passes add arms to `IREmitNode`'s `IR_BINOP` guard chain, and
`IRFirstEvaluated` / `IRStmtFirstEvaluated` MIRROR that chain to decide whether
a reload is redundant — the file says "MUST MOVE TOGETHER" and it means it.
Each new arm was checked against the mirror: all of them evaluate the same node
first as the arm they preempt (const-right -> left first), so the mirrors did
not need to change. The next arm might not be so lucky.

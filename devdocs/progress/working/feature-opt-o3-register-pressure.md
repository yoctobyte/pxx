---
prio: 85
---

# -O3 register-pressure tier: operand scheduler + liveness-scaffold register allocator

- **Type:** feature (codegen — optimization) — **Track O** (Optimization lane;
  file-ownership **Track A** — edits the shared `ir_codegen.inc` / `symtab.inc` /
  backends, so it obeys A's no-concurrent-edit rule + self-host gate) — umbrella
  for the next optimization campaign.
- **Status:** working
  dedicated optimization checkout (`~/frank-optimize`), because Track O is
  implicitly Track A and two agents in `ir_codegen.inc` at once is the hazard the
  track letters exist to prevent. Nothing is half-applied; every commit passed
  the self-host fixedpoint and `gate.sh quick`.
  **Read the two 2026-08-27 sections at the bottom before the older ones — they
  supersede two claims the older text still makes:**
  1. The `-O2` promotion is **DONE** (`13d4bba0c`, `e4fe576eb`, `7767acc60`), and
     it is worth **1.04x, not the 1.29x** quoted below. That figure compared base
     `-O2` against new `-O3` and its baseline no longer exists. **A banked
     speedup decays as the tree moves underneath it** — do not re-quote a number
     from this ticket without rebuilding its baseline.
  2. **W1 now ranks ahead of W2.** Both of W2's cheap experiments came back empty;
     the gap on the hot loops is the operand model, not allocation.
  **Next slice = W1** (emit-time operand scheduler), and it must be justified on
  a *dynamic* profile — the static sweep understates it badly.
  New passes still land behind **`-O3`**; `-O2` stays the proven default.
- **Opened:** 2026-07-10 (post -O2-default flip, [[feature-optimization-levels]]).
- **Owner:** frank-optimize

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

## 2026-08-27 (frankA) — next-slice item 1: both cheap experiments are NO-OPS, and the premise is wrong

Dispatched to work item 1 only ("the three-local loop is still 3x off fpc …
what remains is exactly W2"), running the two experiments the slice says to run
before building anything bigger. **Both are no-ops, the third is near-moot, and
the measurement does not support the premise: what remains on these loops is
W1, not W2.** Nothing was built beyond the instrument.

### The instrument — this time it is COMMITTED

`bench-o/` was scratch and had to be re-created, as the slice warned. The half
that is worth keeping is now a probe rather than a directory:

**`PXXDBG=a.resid`** (`UnifiedResidencyAssign`, committed) prints one `TALLY`
line per residency candidate — proc, sym, loop-access count, type, kind, whether
it escapes, and how many GPRs were free — and one `ASSIGN` line per pick. It
exists because *the eligibility thresholds are invisible in the emitted bytes*: a
local that just missed the cut and one that was never a candidate emit identical
frame traffic, so a disassembly cannot tell you which knob to turn. Reading the
counts is what made both experiments below cheap, and items 2 and 3 of this slice
will want it too.

The timing half stays scratch (three lines of shell): A/B alternating,
`%U` user time, reported as **min of 5** — the box was running Track T's watcher
at load 13 throughout.

**Every number below came from a self-hosted `make compiler/pascal26` fixedpoint
build at this commit, binary sha256 `0b134438899d`.** Two benchmarks, both
`LongInt`/`Int64` (FPC's default mode makes `Integer` 16-bit — the first draft
silently measured a range-check-folded no-op):

- `three.pas` — three locals: `i` (for counter), `j` (temp), `s` (accumulator).
- `many.pas` — six candidates, three free registers: genuine pressure.

Both agree with `fpc -O2` on output at every level tested.

### (a) Lower the eligibility threshold — **no effect**

`three.pas`, min of 5, user seconds:

| threshold | `j` gets a register? | pxx `-O3` | `fpc -O2` |
| --- | --- | --- | --- |
| `> 3` (shipped) | no | 0.79 | 0.34 |
| `> 2` | no | 0.77 | |
| `> 1` | **yes, r15** | 0.78 | |
| `> 0` | yes, r15 | 0.80 | |

`many.pas`, where the pool actually runs out: `> 3` → 0.16, `> 1` → 0.17,
`fpc -O2` → 0.05.

The probe confirms the change *lands* — at `> 1`, `j` (count 2) is assigned r15
next to `s` (5, r12) and `i` (4, r13). It buys nothing, at either threshold, on
either shape.

**Why, and this is the part worth keeping:** residency removes **loads, not
stores** — `EmitStoreVar` dual-writes the frame slot *and* the register, because
the slot stays authoritative. A local with roughly one load and one store per
iteration therefore trades one removed memory read for one added register move
and nets ~zero. `j` is exactly that local. The existing comment's rationale
("plain L1 reloads measured as free — the regcall phase-2 rejection") is
confirmed rather than overturned, so the threshold stays at `> 3`.

The corollary is a better ranking metric for whenever W2 does get built: rank by
**loads**, not by loads+stores. A store-heavy resident is close to free; a
load-heavy one is the whole payoff.

### (b) Use all four free callee-saved registers — **already landed; the slice is stale**

`UnifiedResidencyAssign` already builds its pool as **r12..r15 minus whatever
regcall param residency claimed**, and the probe reports `freegpr=2..4` per body.
The "rather than two" in item 1 describes the pre-unified pass and was overtaken
by the unified-residency work itself. No change; the item is struck.

### (c) A `for` counter should be resident unconditionally — **near-moot**

A `for` counter tallies **4** loop accesses on its own (entry test, bottom test,
increment load, increment store), so it clears `> 3` unaided in the common case —
in `three.pas` it takes r13 with count 4. It loses only when hotter locals
exhaust the pool: in `many.pas`, `i` (4) is beaten by `a`/`b`/`c` (6 each) and
spends the loop in the frame. But forcing it in means **evicting** one of those,
and (a) says the marginal register is worth ~0 there. Not implemented: it would
be policy churn with no measurable payoff behind it.

### What the gap actually is — read off the disassembly

`Run`'s loop body in `three.pas` at `-O3` is **21 instructions** on the common
path. The waste is not allocation:

| pattern | instances per iteration |
| --- | --- |
| `mov %rN,%rax` — operand staged through rax before every use | 5 |
| `mov %rax,%r12` immediately followed by `mov %r12,%rax` | 1 (pure round trip) |
| resident dual-write (`mov %rax,-0x20(%rbp)` + `mov %rax,%r12`) | 2 |
| `j` stored then reloaded from the same slot | 1 |
| for-limit temp reloaded from the frame | 1 |

Every one of those is the **single-accumulator operand model** — that is W1's
subject (the emit-time operand scheduler), not W2's. The register allocator
cannot help a body that moves each value into rax before touching it.

Two things that look like levers and are not, both measured:

- Making the limit a **constant** (no limit temp at all) made `three.pas`
  *slower*, 0.87 vs 0.79. Do not chase the limit temp on its own.
- Across the whole `-O3`-built compiler these patterns are individually small.
  Approximate linear decode of the 9.1 MB text segment, 1.93M instructions
  (approximate because a pxx binary carries no section headers, so the sweep
  decodes data as code in places — read the magnitudes, not the digits):
  dead rax round trip **0.29%**, store-then-reload-same-slot **0.16%**, resident
  dual-write **0.03%**, operand funnel `mov %rN,%rax` **1.21%**.

### Verdict — do NOT start W2 on this evidence

Item 1 asserts "what remains is exactly W2". On the measurement it is not. Both
cheap experiments the slice itself proposed as the gate on that assertion came
back empty, and the third is moot. The remaining gap on both loop shapes is the
operand model, so **W1 (emit-time operand scheduler) should rank ahead of W2**,
and W2's own ranking metric should be loads rather than accesses when it is
built.

Banked and handed back to the coordinator rather than starting W1 unilaterally —
the dispatch was item 1 only. `-O2` promotion untouched (coordinator's call); no
pin taken.

Gate: `make compiler/pascal26` fixedpoint (converged, `0b134438899d`) +
`tools/gate.sh quick` GREEN. The commit adds the probe only; no pass changed
behaviour, so `-O0/-O1/-O2/-O3` output is unchanged by construction.

## 2026-08-27 (frankA) — the `-O2` promotion landed, and its payoff is **1.04x, not 1.29x**

Coordinator's call, three passes, one commit each. All three landed green. But
the number that justified doing this ahead of W1 does not survive being
re-measured, so the record below leads with that.

### What landed

| commit | pass | guards moved |
| --- | --- | --- |
| `13d4bba0c` | div/mod by a constant power of two → shifts/masks | the strength reduction + both zero-check elisions (tkDiv, tkMod) |
| `e4fe576eb` | narrowing ordinal cast → one `movsx`/`movzx` | one (`NarrowCastFold`'s guard) |
| `7767acc60` | cmp-immediate, **both** the branch and value-producing forms | two — they move together, because a short-circuit `and`/`or` lowers each operand to a value, so promoting only the branch form leaves the larger half behind |

Gate constants only; no pass logic changed. Every other `OptLevel >= 3` guard in
`ir_codegen.inc` stays put — float-tree fusion (`FloatTreeFits`), the W1 scratch
arms (`ScratchSafeSubtree` / `CsScratchOn`), and `skipLastArg` are **not** part
of this set and were checked individually rather than swept by pattern.

**`e7c0d1d2a` is deliberately NOT promoted, and this is the fourth pass a future
reader will count and miss.** It fixes the residency refresh so it reads `rax`
rather than the slot it just wrote — and the residency mechanism it repairs is
itself gated `OptLevel >= 3` and does not exist at `-O2`. Promoting it would
change no emitted byte at `-O2`: a no-op wearing the costume of a change. It
stays at `-O3` where it does work.

### Correctness — per pass, differentials re-run after each promotion

Each pass got a checksummed two-oracle differential: `-O0/-O1/-O2/-O3` must agree
with each other **and** with `fpc -O2`, run once **before** the promotion as a
control and again after, with the earlier passes' differentials re-run each time.
Each also confirmed the `-O2` **binary actually changed** — agreement from a pass
that silently failed to fire is worth nothing, and that check is cheap.

- **div/mod:** every power of two through 2^62 and non-powers (10, 3, 7, 100) for
  the zero-check arm, over Int64/LongInt/Cardinal/QWord, dense −300k..300k across
  zero where the sign bias lives, a 40k-point sparse sweep of the full Int64
  range, and the type extremes.
- **narrowing:** every width and signedness, dense −70k..70k plus a 60k-point
  sparse sweep, every width boundary by hand, the hand-written idioms the fold is
  value-identical to, and **four near-misses that must not fold** (partial mask
  `$FE`, 9-bit `$1FF`, mask+xor with no subtract, subtract off by one).
- **cmp-imm:** the imm32 sign-extension boundaries are the whole point — 0, ±1,
  127, −128, imm32 max/min, one past each, 4294967295, 4294967296, the Int64
  extremes — against Int64/LongInt/QWord/Cardinal, six operators, both the branch
  and the value form, plus two short-circuit shapes that exist only in the value
  form.

Self-host fixedpoint after every commit, **converging in 2 rounds rather than 1**
— which is the expected signature here, because the compiler now compiles itself
differently — and `gate.sh quick` GREEN after each.

One case is **excluded and filed rather than papered over**: `QWord div` by a
LITERAL ≥ 2^63 returns a wrong value at `-O0` too, so it is not ours —
[[bug-p-qword-div-by-a-literal-above-2-63-is-signed]]. The sweep divides by the
same value through a variable, which is correct.

### The payoff, measured properly — **1.04x, and the 1.29x was never this**

Method, because the answer depends on it: the baseline must be a compiler whose
**own code** was emitted with the passes off. Built by seeding `552af4dcb`'s
sources from the pinned binary and iterating to a fixedpoint — landing on
`0b134438899d`, byte-identical to the probe-only build measured earlier, which is
what confirms the baseline is genuine. Then A/B alternating, `%U`, min of N.

| workload | pre-promotion `-O2` | post `-O2` | `-O3`-built |
| --- | --- | --- | --- |
| compile `empty.npy` (min of 15) | 2.27 s | **2.19 s** | 2.19 s (min of 9) |
| self-compile `compiler.pas` (min of 3) | 18.31 s | **17.95 s** | — |

**The three promoted passes are worth ~1.04x**, reproduced twice (2.35→2.26 and
2.27→2.19). The entire remaining `-O3` set is worth about another 1.03x on top.

The `1.29x` in the section above is **not** what this promotion could ever have
delivered, and reading it as such is the mistake to avoid repeating:

1. It compared base **`-O2`** against new **`-O3`**, so it always included the
   `-O3`-only passes that are not in the promotable set.
2. Its baseline no longer exists. That row measured 3.65 s for `empty.npy`; the
   same workload is 2.27 s today on the *pre-promotion* binary. Work that landed
   afterwards — `13e196cc8`, emitting the variant clear/retain blobs once instead
   of at 10,707 call sites — had already captured most of that headroom. **A
   banked speedup decays as the tree moves underneath it**, and a figure quoted
   from a ticket months later is a claim about a binary nobody still has.

Not an argument against having promoted them: 1.04x on every compile on every
track, for a change that alters no pass logic and is backed by tens of millions
of differential cases, is a good trade. It **is** an argument against the
priority reasoning that ranked it above W1 on the strength of a stale number.

### Re-ranking: **W1 before W2**

On the evidence in the section above this one, the workstream order at the top of
this ticket is wrong and is superseded:

- **W1 (emit-time operand scheduler) is now the keystone.** Both of W2's cheap
  experiments came back empty, and the disassembly puts 5 of 21 instructions on
  the hot loop's common path in the rax funnel alone. W1 attacks that directly.
- **W2 (linear-scan allocator) drops behind it**, and when it is built its
  ranking metric should be **loads, not loads+stores** — `EmitStoreVar`
  dual-writes, so residency removes reads and not writes, and a store-heavy
  resident is close to free while a load-heavy one is the entire payoff.

A caution for whoever picks W1 up, from this session's own numbers: the static
text-segment sweep put the operand-funnel family at ~1.2% of the binary while the
hot loop shows 24% on its common path. Those are not in conflict — a static count
weights cold code equally — but it does mean **W1 must be justified on a dynamic
profile, not a static one**, and its win will land on hot loops rather than on
overall code size.

## 2026-08-27 (frank-optimize) — W1 sized before building: it is worth **1.4%**. The prize is the residency ADMISSION METRIC, and it is already shipped

**A loop-carried accumulator must never sit in the frame while GPRs idle.**

Dispatched to size W1 (the emit-time operand scheduler) before committing to it,
after frankA's run above found the operand funnel — 5 of 21 instructions on the
common path — and concluded "a register allocator cannot help a body that moves
every value into rax before touching it". That is true. It is also true that
*removing* those movs helps nothing, and this slice measures both halves.

Nothing was built. No pass changed. The whole result is one A/B harness.

### Method — hand-written asm, calibrated at BOTH ends before it was used

`Run`'s actual `-O3` disassembly (17 instructions on the common path, `i`
resident in r12, `s`/`j` in the frame) was transcribed into raw asm, then
successively optimized into five variants, all six timed in one process.
The next reader's first instinct will be to distrust a hand-written asm model,
so it was calibrated against the two things it sits between:

| | model | real binary |
| --- | --- | --- |
| shipped `-O3` body | 1.147 s | **1.14 s** (pxx `-O3`) |
| ideal allocation | 0.171 s | **0.23 s** (`fpc -O2`) |

It reproduces the thing being modelled *and* the target being chased. A model
calibrated at neither end is a story; this one is evidence.

Every variant returns the identical result (`-200000002`), which is also what
pxx at `-O0/-O1/-O2/-O3` and `fpc -O2` print for the same source.

### The decomposition

Binary sha256 `591ae8160f69...` (self-hosted fixedpoint at HEAD, confirmed
different from `pinned`). Box at load 7-13 (Track T's watcher); `%U` user time,
A/B alternating, min of 5. `three.pas` = `j := i xor s; s := s + j` over
200M iterations, three `LongInt` locals in a procedure.

| variant | s | cyc/iter | vs shipped |
| --- | --- | --- | --- |
| V0 — the shipped `-O3` body (17 insns) | 1.142 | 12.00 | 1.00x |
| **V1 — W1 applied: all three `mov %rN,%rax` funnels + the dead round trip gone (11 insns)** | **1.133** | 11.89 | **1.01x** |
| V4 — `s` also resident, dual-write kept | 0.702 | 7.37 | 1.63x |
| V2 — W1 + store->reload elimination | 0.630 | 6.61 | 1.81x |
| V5 — all three resident, dual-write kept | 0.368 | 3.86 | 3.10x |
| V3 — true allocation, no frame traffic (fpc-like) | 0.171 | 1.79 | 6.68x |

**W1 buys 1.4% on the exact loop that motivated it.** Deleting 6 of 17
instructions moved nothing measurable: those instructions were never on the
critical path. (Mechanism is almost certainly move elimination at rename on this
Ivy Bridge Xeon, but the measurement does not depend on the explanation.) The
5-of-21 static share is real and irrelevant — **do not build the operand
scheduler for speed.** Its residual value is code size (-35% on this body,
~1.2% image-wide by frankA's sweep), which is a different and much weaker case.

What the 12 cyc/iter actually is: **two frame round-trips on the loop-carried
dependency chain at ~5 cycles each** (store-to-load forwarding), plus ~2 cycles
of real work. Each variant above removes exactly one such round trip and pays
back exactly one forwarding latency — V1->V2 removes `j`'s store+reload (-5.3
cyc), V2->V3 removes `s`'s (-4.8 cyc). The model is that simple.

### Why the threshold experiment came back empty — this CONFIRMS frankA's run, it does not correct it

`PXXDBG=a.resid` (frankA's probe, and it is what made this cheap) on this body:

```
TALLY proc=Run sym=i count=4 ... freegpr=4     ASSIGN sym=i reg=r12
TALLY proc=Run sym=s count=3 ... freegpr=4
TALLY proc=Run sym=j count=2 ... freegpr=4
```

**`s` misses the `> 3` cut by one, with three registers sitting idle.** Giving
`s` a register is worth 1.63x on its own (V4); all three, 3.10x (V5) — keeping
the dual-write exactly as designed.

frankA's `three.pas` already had `s` resident at count 5, so lowering the
threshold there only ever admitted `j` — one load per iteration, the load-poor
candidate, correctly worth ~0. Their conclusion *"the threshold stays at > 3"*
is right. The measurement's actual content is that **the METRIC is wrong, not
the threshold** — and their own corollary, *rank by LOADS, not accesses*, turns
out to be the pass itself rather than a footnote for a future W2. Two runs from
different angles converging on the same mechanism.

### Revised ranking (adopted by the coordinator, 2026-08-27)

1. **Residency admission by LOADS, and never leave free GPRs idle** — a small
   change inside the shipped `UnifiedResidencyAssign`. Up to 3.1x on tight
   scalar loops. **Land behind `-O3`:** unlike today's promotions this changes
   *which* programs get *which* registers, so it is not gate-constant — full
   `-O0/-O1/-O2/-O3` + `fpc -O2` differential, self-host fixedpoint per commit.
2. **Store->reload elimination for resident destinations** — the `ReloadElimSym`
   exclusion whose stated reason stopped being true at `e7c0d1d2a`.
3. **Drop the dual-write inside a loop** (register authoritative, frame re-synced
   at exits). V5->V3 is a further 2.15x. This is the real W2 and the big job.
4. **W1** — deprioritised to a code-size item.

### Scope limit, stated up front

This bounds **tight scalar user code** (mandelbrot-class). It does **not** bound
the self-compile, which this ticket already measures as memory-bound and which
took only 1.05x from residency. When item 1 lands, `make compiler/pascal26` gets
measured and reported as **its own number even if it is ~1.0x** — a pass that is
3x on mandelbrot and 1.0x on the compiler is still worth having; a pass claimed
at 3x that nobody separated is how a ticket ends up carrying a stale 1.29x.

Harness (six asm variants + driver) was scratch, not committed — it is ~120
lines of asm and the bodies are transcribed above and in frankA's disassembly
table, which is what a re-run needs.

## 2026-08-28 (frank-optimize) — item 1 LANDED at `-O3`: residency admits and ranks on LOADS. **1.9-2.1x on tight scalar loops, and ~2-6% SLOWER on the self-compile.** Both numbers are real

The slice the sizing above ranked first. `UnifiedResidencyAssign` now tallies
loop **loads** separately from total accesses, ranks candidates on loads, and
admits any candidate with at least one loop load while a register is free — the
bound is the register pool, not a threshold.

Diff is 35 lines in `ir_codegen.inc`. Binary `fc9d664a4e63`.

### Why loads, restated at the point of change

Residency removes **reads**. `EmitStoreVar` dual-writes — the frame slot stays
authoritative — so a store costs one extra register move, which is free. The
old test, `Counts[k] <= 3` over loads AND stores, therefore ranked on a number
whose store half it cannot cash: it let a store-heavy local outrank a
load-bearing one, and on this ticket's own benchmark it excluded the accumulator
`s` at exactly 3 accesses **while three registers sat idle**.

### The numbers, and they disagree with each other

`-O3`-built compilers, both from the same source; `%U` user time, A/B
alternating in a single run, min of N. Box under Track T's watcher at load 8-13
throughout, which matters — see the noise note below.

| workload | before | after | |
| --- | --- | --- | --- |
| `three.pas` (three-local loop) | 1.15 s | **0.61 s** | **1.89x** (a second run: 1.33 -> 0.62, 2.15x) |
| mandelbrot | 1.20 s | 1.09 s | within noise — its kernel is float, this is an int-side change |
| sieve | 0.03 s | 0.02 s | too short to time |
| **self-compile of `compiler.pas` at `-O3`** | **16.57 s** | **17.58 s** | **~6% SLOWER** |

The self-compile regression reproduced in all three runs that measured it
(20.87 -> 21.22, 16.57 -> 17.58, 15.47 -> 16.05: +1.7%, +6.1%, +3.7%). The sign
is consistent even though the magnitude is not, so it is real.

**`make compiler/pascal26` — the number every lane actually pays — is
unaffected**, by construction and by measurement: the pass gates `OptLevel >= 3`
and the build uses the default level. An 8-program corpus x 6 targets = 48
output hashes is byte-identical before and after.

**Why the compiler loses while the loop wins.** Residency's benefit scales with
loop TRIP COUNT; its cost — prologue save, init load, epilogue restore — is paid
per CALL. A body that *is* a loop pays the fixed cost once and wins big. A
small, hot, call-per-item body with a short loop pays it constantly. The
compiler is the second shape and `three.pas` is the first. That is the real
finding here, and it is what the next slice has to price.

**Tightening admission does NOT fix it — measured, so nobody retries it.**
`loads >= 3` (roughly the old admission volume, ranked the new way) is worse on
*both* workloads: self-compile 17.33 s (+12% vs before, worse than `>= 1`) and
`three.pas` 1.17 s (giving up nearly the whole win). `loads >= 2` was also
tested and sits between. So the regression is not "too many residents", and the
per-call cost story above is a hypothesis the next slice must test rather than
a conclusion this one proved.

### Correctness

- **`-O0`/`-O1`/`-O2`/`-O3` agree with each other AND with `fpc -O2`** on a
  purpose-written residency stress (every store overflows its declared type, so
  a missing re-extension shows at once: Byte/Word/ShortInt/SmallInt wrap; seven
  live candidates against four registers; residents written inside a `try` block
  that raises mid-loop, exercising the `IR_EXC_ENTER` landing-pad refresh;
  nested procedure writing an enclosing local; recursion; a float loop) plus
  arrays/records/strings/exceptions/hello. The **only** divergence anywhere is
  the last two digits of one float print, which is **identical on the
  pre-change compiler** — pre-existing, Track F, not this slice's.
- `-O3` **self-host fixedpoint byte-identical** (`fc9d664a4e63`) after every commit.
- The `-O3`-built compilers from before and after this change produce
  **byte-identical output** compiling `compiler.pas`.
- **`-O2` and all four cross targets unmoved**: 48/48 corpus hashes identical.
- `tools/gate.sh quick` GREEN.

### Two process notes worth more than the patch

**A 7% "regression" that was noise, and it nearly became a source comment.**
Mid-slice, mandelbrot measured 1.10 s before and 1.18-1.24 s after. I built a
per-class rank split to fix it and wrote the cause into the code as fact.
Re-measuring all three binaries *in one interleaved run* put them at 1.34 /
1.33 / 1.34 — the same "before" binary that had measured 1.09 now measured 1.34.
The effect was the box, not the change. The split was reverted (the rebuilt
binary is bit-identical to the pre-experiment one, which is how the revert was
verified) and the comment now records that the two rankings are
indistinguishable. **On this box, min-of-N across separate invocations is not
enough; only binaries timed inside the same interleaved run are comparable**,
and a causal comment must not be written from a delta measured across runs.

**A corpus diff that was also an artifact.** The `-O2` byte-identity check
initially flagged `exc` as changed on all six targets, which for an `-O3`-gated
pass should be impossible. It was: `exc` is the only corpus program that `uses
SysUtils`, and a `git pull` between the two hash runs (the v389 pin) had updated
`lib/rtl` underneath. Re-running **both** sides back to back gave 48/48.
Compare against a baseline you regenerate now, not one from earlier in the
session.

### 2026-08-28 — CORRECTION to the entry above: the self-compile regression was not real either

The `~2-6% slower self-compile` reported for item 1 does not survive a
properly-powered measurement, and the number should not be used. It was
produced the same way the mandelbrot artifact was — interleaved, but with only
3-4 repetitions of a 17-second workload on a box whose load moved between 8 and
16. "Reproduced in three runs" was three under-powered runs sharing a bias, not
three confirmations.

Re-measured, all interleaved in single runs:

| workload | reps | before | after | |
| --- | --- | --- | --- | --- |
| self-compile of `compiler.pas` at `-O3` | **min of 6** | 16.92 s | 16.97 s | **+0.3%** |
| compile `hello.pas` | min of 15 | 0.20 s | **0.16 s** | new is FASTER |
| compile the residency stress program | min of 15 | 0.58 s | 0.58 s | identical |
| `callheavy` (trip count 3, 20M calls) | min of 7 | 0.56 s (`-O2`), 0.56 s (old `-O3`) | **0.51 s** | new is FASTER |
| `looplong` (same body, trip count 3000) | min of 7 | 0.23 s | **0.20 s** | new is FASTER |

**So the honest summary of item 1 is: 1.9-2.1x on tight scalar loops, and
neutral-to-slightly-positive everywhere else measured.** No workload measured
here is slower.

**The hypothesis the regression supported is also dead, and it was tested
directly rather than abandoned.** `callheavy` was written specifically to be the
shape the per-call-cost story predicts a loss for — a small body, a three-
iteration loop, twenty million calls — and residency makes it 9% **faster**, not
slower. Residency's save/init/restore is evidently cheap relative to what even
three iterations of removed loads buy. The "benefit scales with trip count,
cost is per call" model is not wrong in principle, but the per-call cost is too
small to have produced the regression that motivated it, because there was no
regression.

What this does NOT change: the `loads >= 3` result (worse on both workloads)
stands — it was measured inside a single interleaved run against both
comparators. And `-O2` remains untouched and byte-identical, which was never a
timing claim.

**Method, now applied to itself.** The entry above this one records the lesson
that only binaries timed inside one interleaved run are comparable. That was
right and insufficient: this measurement WAS interleaved and still wrong,
because **3-4 reps cannot resolve a 5% effect on a 17-second workload on a
contended box.** The playbook entry has been extended accordingly. The
generalisable form: interleaving fixes *which* runs you compare, repetition
fixes *how confidently*, and a short workload with many reps beats a long
workload with few. `hello.pas` at min-of-15 gave a cleaner answer in two
minutes than `compiler.pas` at min-of-3 gave in ten.

### 2026-08-28 — item 2 (store->reload elimination for resident destinations): DISCONFIRMED, and item 1 is why

Claimed and measured. **The exclusion should stay.** No pass changed; the
outcome is a corrected comment and this entry.

The ticket says `ReloadElimSym` excludes resident destinations for a reason
that "is no longer true after `e7c0d1d2a`". That is right about the reason and
wrong about the conclusion, because the exclusion had **two** reasons:

- **(a) stale, as the ticket says.** "The resident dual-write refreshes through
  `EmitLoadVar` and so clobbers rax" — the refresh now re-extends from rax
  itself, so rax does still hold the stored value. Dead.
- **(b) still true, and now measured.** A resident load is ALREADY a reg-reg
  move (`mov %r13,%rax`). Eliminating it removes a register move, not a memory
  access.

Dropping the exclusion and rebuilding, on `bt.pas` — a loop over
`if (c >= 'A') and (c <= 'Z')`, the exact shape item 3 names — removes **6
instructions out of 13,483**, every one a reg-reg move. That is the class the
W1 sizing in this ticket already priced at ~0 (deleting 6 of 17 such moves from
a hot loop body moved the clock 1.4%). Not worth timing; not worth landing.

**Item 1 is what emptied it.** Before item 1 the boolean temp lived in the
frame and the sequence was a genuine memory round trip —
`mov %al,-0x1d(%rbp); movzbq %al,-0x1d(%rbp)` — which is what made item 2 look
valuable when it was filed. At `-O3` today that temp is **resident in r14**, and
the emitted body of `Upcount` contains exactly one memory READ, the string byte
itself. There is no reload left to eliminate:

```
setae  %al
movzbq %al,%rax          <- extend
mov    %al,-0x1d(%rbp)   <- dual-write (a STORE; off the critical path)
movzbq %al,%rax          <- re-extend from al, not a reload
mov    %rax,%r14         <- refresh resident
```

**Where the remaining value actually is, and it is item 3.** What survives in
that body is the **dual-write stores** — `mov %al,-0x1d(%rbp)`,
`mov %eax,-0x14(%rbp)`, `mov %eax,-0x10(%rbp)` per iteration — not reloads.
Removing those means making the register authoritative inside the loop and
re-syncing the frame at exits, which is the V5 -> V3 step the sizing measured at
a further **2.15x**. That is the real W2, and it is now the only unclaimed item
in this ticket with measured value behind it.

So the ordering the sizing proposed survives contact: item 1 landed and was
worth 1.9-2.1x; item 2 is empty *because* item 1 landed; item 3 is the job.

## STANDING RULE for this umbrella: re-measure the PRIZE before starting an item, not just the mechanism

Every item in this ticket was sized against a compiler that has since changed.
Twice in one session an item's stated prize turned out to have been consumed or
created by a *different* item landing:

- **item 2 was emptied by item 1.** Filed when the boolean temp lived in the
  frame and its store/reload was a real memory round trip; by the time it was
  claimed the temp was resident and there was no reload left to remove.
- **W1 was REVIVED by item 1** (below). Correctly disconfirmed at 1.4% against
  the compiler as it stood; the same transform is now worth ~1.6x, because item
  1 removed the memory traffic that had been hiding it.

A stale prize is more expensive than a stale number, because it does not look
like a claim to re-check — it looks like work waiting to be done. So: before
starting an item, disassemble the current output and re-measure. It costs
minutes.

## 2026-08-28 (frank-optimize) — item 3 sized before building: worth **~5%**, and W1 is now worth **~1.6x**. The order inverts

Dispatched to item 3 (make the register authoritative inside the loop, re-sync
the frame at exits). Sized it first per the rule above. **Do not build item 3
next; build W1.**

### Why the old 2.15x was wrong — it measured two changes at once

The V5 -> V3 step in the sizing entry above (0.368 -> 0.171 s) was read as the
price of the dual-write stores. It is not. V5 and V3 differ by the stores **and**
by all the operand staging through rax; V3 was an idealised 6-instruction body,
not V5-minus-stores. The 2.15x is the two transforms together.

### The isolated measurement

`Run`'s **current** `-O3` body, transcribed from today's disassembly (21
instructions, and note it now contains **zero memory reads** — item 1 removed
them all; the only frame traffic left is three dual-write stores). Variants
differ from A by deletion only. Interleaved in one process, min of 9-12, four
independent runs agreeing.

| variant | s | cyc/iter | vs current |
| --- | --- | --- | --- |
| **A — current `-O3`** (21 insns, calibrates: real binary 0.61 s) | 0.616-0.654 | 6.5 | 1.00x |
| **B — item 3 exactly: the three dual-write stores deleted, nothing else** | 0.593-0.618 | 6.3 | **1.04-1.06x** |
| **C — item 3 + W1: staging through rax also gone** (11 insns) | 0.365-0.385 | 3.9 | **~1.65x** |
| D — ideal, fpc-like (6 insns) | 0.193-0.216 | 2.1 | 3.0x |

**Item 3 alone is ~5%.** Stores retire into the store buffer and are off the
loop-carried dependency chain, so deleting them buys close to nothing — the
same reason the *loads* mattered so much is why the stores do not.

**B -> C is ~1.6x, and that is W1** — the emit-time operand scheduler this
ticket deprioritised this morning on my own measurement.

### Why W1's value changed, which is the transferable part

W1 was sized at **1.4%** against the pre-item-1 compiler and that number was
correct. At the time the body was 12 cyc/iter dominated by two frame
round-trips; every `mov %rN,%rax` sat in their shadow, and deleting six of them
moved nothing. Item 1 removed the memory traffic. The body is now 6.5 cyc/iter
and the dependency chain runs **through the staging moves themselves** — the
value is threaded `r13 -> rax -> r14 -> rcx -> rax` between the xor and the add.
The same instructions that were free when they overlapped a 5-cycle
store-forward are the critical path once the store-forward is gone.

**An optimisation's value is not a property of the transform. It is a property
of the transform against a specific baseline** — and this ticket's baseline
moved this morning, by our own hand.

### Recommendation

1. **W1 — emit-time operand scheduler.** ~1.6x on this shape, now measured
   twice from opposite directions. Un-deprioritise it; it is the item that
   inherits item 1's win.
2. **Item 3 — register authoritative.** ~5%, and it is the *harder* of the two
   (exit re-sync, exception landing pads, every path that reads the frame slot
   as authoritative). Worst effort-to-payoff ratio in the ticket right now.
3. The far end (D) is another ~1.8x beyond C, and is a real allocator.

Nothing built, nothing changed. Handing the inversion back to the coordinator
rather than switching items unilaterally — the dispatch was item 3.

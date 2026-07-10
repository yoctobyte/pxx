---
prio: 65  # auto
---

# Optimization levels (`-O0/-O1/-O2/-O3/-Os`) + pass framework

- **Type:** feature — umbrella — **Track O** (Optimization lane; file-ownership Track A)
- **Status:** backlog — **-O2 IS THE DEFAULT as of 2026-07-10 (pinned v194).**
  OptLevel default 0→2; ~1.34x faster / ~11% smaller; self-host -O2 fixedpoint
  byte-identical; `make test` + `make test-opt` green. `-g` now implies `-O0`
  unless an explicit `-O` is given (opt relocates/elides debug lines). The
  missed-fold tripwire is now opt-in (`--warn-missed-fold`) since inline (-O2)
  legitimately produces foldable BINOPs on nearly every compile. The blocking
  disassembler miscompile ([[bug-a-o2-miscompiles-disassembler]], the r14/r15
  residency re-emit) is fixed. Const-fold/identities revival is now worth
  re-measuring under -O2 ([[feature-revive-const-fold-identity-pass]]).
  **-O1 arc DELIVERED + pinned (v171); higher tiers pending.**
  Moved out of working/ 2026-07-04 (no longer actively worked; not half-applied
  — every landed pass is clean + self-host byte-identical). -O1: passes 1-4
  (operand direct-load, compare-into-branch fusion), imm-fold, shared-IR
  pass framework + DCE/redundant-jump, pin flipped to -O1-built. Rejected
  (measured 0-fire): const-fold, algebraic identities, if-false DCE, strength
  reduction — all tripwired. Remaining tiers are separate tickets:
  [[feature-callconv-register-args]] (-O2 regcall, the big self-compile win),
  [[feature-inline-routines]]. Full method: `devdocs/dev/optimization-architecture.md`.
- **Owner:** —
- **Opened:** 2026-06-20 (design discussion — optimization strategy)
- **Priority:** ~~last~~ **GREENLIT 2026-07-03** (user decision): pin-time is
  now the bottleneck (several minutes per pin; goal ~20s — see
  [[chore-fast-pin-tiered-tests]]), and the language/RTL surface has settled
  enough. Start with the low-hanging -O1 peepholes below.

## Target scope (Track O policy)
**Per-backend optimization effort = x86-64 + aarch64 only.** Shared-IR passes
(§3a) help all six targets for free and stay target-agnostic; per-backend work
(emitter peepholes, register allocator/scheduler) is built only for the two
targets where compiled-code throughput matters. 32-bit (i386/arm32/rv32) is
perf-irrelevant (legacy/control/bring-up, not throughput); ESP32/xtensa is a
special case whose hot paths are hardware peripherals (DMA/ADC/SPI, already
supported), not compiled loops. Don't port per-backend passes to those.

## Motivation

PXX is single-pass and emits straightforward code: full prologue/epilogue per
call, naive register use, no cross-statement reasoning. That is correct and
keeps self-host byte-identical tractable, but leaves easy cycles on the floor —
especially in hot loops and on the cycle-starved ESP targets. We already do
*partial constant folding at -O0* (kept, it is local and invisible). The goal of
this ticket is a **deliberate, level-gated optimizer**: a small set of cheap,
safe, deterministic passes, each independently landed, tested, and self-host
verified, organised behind the conventional `-O` flag.

## No standard, but a conventional shape

There is no ISO/standard mandate for what `-O1/2/3` must do — GCC/Clang/MSVC only
loosely agree. We adopt the convention and assign passes per-feature by the
**safe vs. some-risk** axis, not by a rulebook:

| Level | Contract | Notes |
|-------|----------|-------|
| `-O0` | none beyond existing partial const-fold; **1:1 source↔asm**, debuggable | dev default; protect this contract |
| `-O1` | cheap, safe everywhere, **no code-size blowup**, deterministic | candidate to become the *default* once proven |
| `-O2` | full speed; code size may grow; some heuristics | release default |
| `-O3` | aggressive; may not always pay (icache, codegen risk); benchmark-gated | opt-in |
| `-Os` | size-first; O2 minus anything that grows code; inline only if net-smaller | matters for ESP/xtensa/riscv |

Level assignment is **not written in stone** — per pass we pick the level by
whether it is *proven safe with issue detection* (then it can sit at O1) vs.
*correct but carrying some risk* (O2). Example: `inline;` (see
[feature-inline-routines](feature-inline-routines.md)) graduates from O2 to O1
once it reliably detects ineligible bodies and degrades to a call.

## Architecture decisions

- **Optimize on the shared IR, not per-backend.** One pass implementation
  benefits all five targets at once and gives a single uniform self-host gate.
  AST-level only for things that genuinely need source shape (existing const
  fold). Backend-specific wins (shift-strength reduction, addressing modes) =
  peephole on shared IR, never duplicated into each emitter — that keeps
  byte-identical tractable.
- **Pass framework first.** A thin ordered pass pipeline keyed off the `-O`
  level, so each optimization lands as one self-contained pass with its own
  enable level. Avoids a monolithic "O1 mode".
- **Per-feature override knob from day one.** Global `-O2` but local
  `{$optimize off}` / `{$O-}`..`{$O+}` scope (FPC-compatible), so a user can
  disable optimization around a miscompiling hot spot without dropping the whole
  build.

## Hard gates (ticket-level, non-negotiable)

1. **Determinism.** No heuristic may depend on pointer values, allocation
   addresses, or hash/map iteration order. Cost models count IR nodes (stable),
   nothing address-derived. Non-determinism breaks self-host fixedpoint.
2. **Self-host byte-identical at every shipped `-O` level.** The compiler must
   self-compile byte-identical at each level it offers. This is an N×M matrix
   (levels × targets) — start O1-only to keep it small, grow deliberately.
3. **Cross-level output-equality oracle.** The cheapest strong test: the same
   program compiled `-O0` vs `-O1` vs `-O2` must produce **identical runtime
   output**. Any behaviour change = optimizer bug, caught immediately. Wire into
   `make test` per pass.
4. **`-O0` stays 1:1 debuggable.** Do not sneak in folds/motions at O0 that
   disturb source↔asm line mapping. Existing local const-fold is fine.
5. **Volatile Support before Optimizing.** To prevent incorrect elision of memory accesses (especially on MMIO / hardware boundaries), `volatile` semantics MUST be fully parsed, mapped, and enforced in the AST/IR before any optimization passes (such as dead store elimination, redundant load elimination, or loop-invariant code motion) are enabled.


## Candidate passes (assign levels as proven)

**O1 (cheap, safe, no growth):**
- Complete constant folding (incl. the gaps — e.g. `Int64()` const cast can't
  fold today, see [feature-const-eval-typecast-int64](feature-const-eval-typecast-int64.md)).
- Dead-code elimination — unreachable after `exit`, `if false`, etc.
- Local copy propagation / redundant-load elimination (single block).
- Algebraic identities (`x*1`, `x+0`, `x*2`→`shl`) — shift-strength as IR peephole.
- Jump-to-jump / branch threading.
- Tiny-leaf auto-inline — only where inlining is *provably not larger* (call
  sequence ≥ body), no cost-model measurement needed.
- Short-form (rel8) branch encoding in `EmitAsmX64`'s forward-label idiom
  (`asmtext.inc`'s `.label`/`jz .label` mechanism, used pervasively for
  `.done`-style short jumps in `ir_codegen.inc`'s ARC helpers). It always
  emits the 6-byte near/rel32 form even when the target is a few bytes away
  and a 2-byte rel8 `jz`/`jnz`/`jmp` would do — 4 bytes/use, deterministic,
  found while re-verifying `EmitAsmX64` against `llvm-mc` in
  [[bug-emitasmx64-heap-helpers-oom-selfhost]]. Backward labels already
  resolve at fixed distance so could pick short-form directly; forward labels
  would need a two-pass size-then-patch (or over-allocate then shrink) — same
  shape as any assembler's branch-relaxation pass.

**O2 (speed, size may grow):**
- `inline;` honored generally + aggressive auto-inline behind a node-count cost
  model ("comparable or shorter code" heuristic). Hosted by
  [feature-inline-routines](feature-inline-routines.md).
- Common subexpression elimination (cross-block).
- Loop-invariant code motion.
- Strength reduction in loops.
- Register-allocation upgrade if the current naive scheme proves spill-heavy.

**O3 (aggressive, gated):**
- Loop unrolling.
- Inline-everything-non-recursive.
- (Vectorization — far off, listed only for completeness.)

**-Os (ESP/embedded):**
- O2 set minus any code-growing pass; inline only when net-smaller; favour
  `chore-runtime-emission-size` wins.

## Build-out order (split into sub-tickets only when work starts)

Keep this as a single umbrella for now — do not flood the board. When work
begins, split per pass so each lands + reseeds (`make bootstrap`) + self-host
verifies independently, matching the fine-grained-commit norm. Suggested first
four (each independently testable, low risk):

1. Pass framework + `-O` flag plumbing + `{$O±}` scope + cross-level oracle harness.
2. Constant-folding completion.
3. Dead-code after `exit` / `if false`.
4. Tiny-leaf provably-not-larger auto-inline (ties into feature-inline-routines).

## Acceptance

- `-O0/-O1` selectable; `-O1` passes run, `-O0` output unchanged from today.
- Cross-level output-equality oracle green; `make test` green.
- Compiler self-compiles **byte-identical at each shipped level**;
  `make cross-bootstrap` byte-identical on i386 + aarch64 + arm32.
- A measured win (cycles and/or code size) on at least one real workload with no
  correctness regression.

## Related

- [feature-inline-routines](feature-inline-routines.md) — inlining mechanics; a
  pass this framework hosts and gates by level.
- [feature-allocator-quality](feature-allocator-quality.md),
  [chore-runtime-emission-size](chore-runtime-emission-size.md) — adjacent
  "make it smaller/faster" work, measured not speculative.
- [feature-const-eval-typecast-int64](feature-const-eval-typecast-int64.md) —
  a known const-fold gap to absorb.

## Log
- 2026-06-20 — ticket opened from optimization design discussion. Decisions:
  optimize on shared IR; pass framework keyed off `-O`; per-pass level by
  safe-vs-risk not rulebook; four hard gates (determinism, per-level self-host,
  cross-level output oracle, O0 stays 1:1). Optimization is the last arc.

## Measured baseline + concrete low-hanging fruit (2026-07-03, v162)

`make benchmark-compiler-runtime`: identical compiler source, FPC-built binary
5.1s vs pxx-built 10.4s for the same self-compile — generated code is
**2.04x slower and 1.97x larger** (4.06MB vs 2.06MB). That gap is the -O
budget. Sibling axes: [[perf-compiler-hotspots-algorithmic]] (compiler's own
algorithms: FindProc linear scans = 13% of self-compile),
[[feature-callconv-register-args]] (the -O2 ABI flag-day),
[[feature-inline-routines]] (-O1/-O2 inlining).

Cheapest first, all -O1 candidates (deterministic, local, peephole over the
emitted stream or one-node IR context):

1. **push/pop pair elision** — the stack-machine emits `push rax … pop rcx`
   around nearly every binary op even when nothing intervenes; a small
   emitter-level window (track last-emitted push, cancel matching pop into
   `mov rcx, rax` or direct register use) removes two memory ops per operand
   pair. Biggest single win, everywhere.
2. **redundant load elimination** — `mov [slot], rax` immediately followed by
   `mov rax, [slot]` (store-then-reload of the same slot) drops the reload.
   Very common at statement seams.
3. **constant peepholes** — `mov rax, 0` -> `xor eax, eax` (7 bytes -> 2);
   `add rax, 1`/`sub rax, 1` -> `inc/dec`; compare-with-0 after arithmetic
   that already set flags. Mostly size, some speed.
4. **IR_CONST_INT into BINOP immediates** — `mov rcx, imm; add rax, rcx` ->
   `add rax, imm` when the constant fits imm32. Kills a register shuffle per
   constant operand.
5. **branch-over-branch** — `jcc +2; jmp target` -> `j!cc target` where the
   pattern appears from the comparison lowering.
6. **dead store to hidden temps** — lowering-time temps written once and read
   once immediately after can bypass the frame slot entirely (subset of 2).

Suggested pass placement: 1–5 as an emitter-side peephole ring buffer (no IR
change, applies to every backend that opts in — x86-64 first); 6 wants the
liveness scaffold shared with [[feature-callconv-register-args]].

Gate discipline per the table above: -O0 stays byte-identical (the self-host
gate is UNCHANGED); each -O1 pass lands with a codegen-diff test (compile a
corpus at -O0/-O1, run both, identical output) + `make test` under an
-O1-built compiler + benchmark delta recorded here.

## Progress — -O plumbing + pass 1 LANDED (2026-07-03)

- `-O0..-O3` flag -> `OptLevel` (defs/compiler.pas); default 0, and every
  pass gates on its tier, so the -O0 self-host byte-identity gate is
  untouched by construction.
- **Pass 1 (-O1): leaf-const BINOP operand direct load** (x86-64). A
  constant right operand loads straight into rcx (`mov rcx, imm32/imm64`)
  instead of push-left / eval-right / mov / pop — two stack ops and a
  register shuffle gone per constant operand. Register contract downstream
  is byte-for-byte identical (rax=left, rcx=right), so every consumer —
  including the string-concat and float branches — is untouched.
- **Gate: `make test-opt`** — 12-program differential corpus (each compiled
  -O0 and -O1, runtime output cmp'd) + the -O1 self-compile fixedpoint
  (-O1-built compiler rebuilds itself at -O1 to byte-identity). Also ran the
  FULL `make test` under an -O1-BUILT compiler: green.
- **Measured**: -O1-built compiler self-compiles in 4.64s vs 5.5s (-O0 built)
  — ~16% faster; test binaries ~10% smaller (e.g. hello-class corpus
  41.9k -> 37.0k). One pass.

OPEN DECISION: pins stay -O0-built for now (byte-identity continuity for
B/C). Flipping the pinned binary to -O1-built is free performance for every
track once we trust the pass battery — revisit after 2-3 more passes.

## Progress — pass 2 LANDED (2026-07-03)

- **Pass 2 (-O1): leaf-sym BINOP operand direct load** (x86-64). Extends
  pass 1 from constants to side-effect-free scalar `IR_LOAD_SYM` right
  operands: a plain local/param/global loads straight into rcx
  (`EmitLoadVarRcx`, symtab.inc) after the left value is in rax — the
  push-left / eval-right-into-rax / mov rcx,rax / pop-rax dance collapses to a
  single load. Order-safe because a plain load has no side effects; the direct
  rcx target avoids clobbering the left in rax. Register contract downstream
  IDENTICAL (rax=left, rcx=right).
- **Guard `LeafSymRcxLoadable`** (symtab.inc) admits ONLY skLocal /
  skParam(non-ref) / skGlobal non-float, non-string(tyString/tyAnsiString/
  frozen), non-array scalars. Every managed / float / by-ref / frozen /
  skConst path stays on the general push/pop route untouched — the win is
  Integer/Int64/Cardinal/pointer/char/bool/enum loads. `EmitLoadVarRcx`
  mirrors `EmitLoadVar`'s scalar else-branch byte-for-byte with the reg field
  switched rax(000)->rcx(001) ([rbp+disp] ModRM 85->8D; [abs] 04 25->0C 25;
  mov eax->mov ecx).
- **Gates**: `make test-opt` green (differential corpus + -O1 fixedpoint,
  code=3779988B). `-O0` self-host fixedpoint byte-identical (sacred gate
  UNTOUCHED — every branch gates `OptLevel >= 1`). FULL `make test` under an
  -O1-BUILT compiler (pass 1+2): EXIT=0.
- **Measured** (hyperfine -w2 -r5, self-compile): -O1-built (pass 1+2)
  4.545s vs -O0-built 5.710s = **1.26x faster** (~20%); pass 2 adds ~4pts
  over pass 1's 16%. -O1-built compiler binary 3.89MB vs -O0-built 4.06MB.

## Progress — pass 3 LANDED (2026-07-03)

- **Pass 3 (-O1): constant-load size peephole** (x86-64) in `MovRaxImm`
  (emit.inc, the single choke point for constant->rax loads; x86-64-only,
  the 32-bit/ARM/RISC-V backends never call it). The historic form is always
  10-byte `movabs rax, imm64`; under -O1: `v=0` -> `xor eax,eax` (2B),
  `0..2^32-1` -> `mov eax,imm32` (5B, zero-ext), `-2^31..-1` -> `mov rax,imm32`
  (7B, sign-ext). Every consumer only needs rax = v; all three extend to the
  full register.
- **Gates**: `make test-opt` green (-O1 self-code shrank 3.78MB -> 3.58MB,
  ~200KB from this pass alone). `-O0` self-host fixedpoint byte-identical
  (sacred gate untouched). FULL `make test` under an -O1-BUILT compiler
  (pass 1+2+3): EXIT=0.
- **Measured**: primarily a SIZE win — -O1-built compiler binary 3.69MB vs
  -O0-built 4.06MB (~9% smaller; ~200KB below pass-2's 3.89MB). Self-compile
  speed steady 1.25x (xor/mov-eax are >= movabs speed, no regression; icache
  benefit). Constant loads are pervasive so the byte savings compound across
  the whole binary.

## Store-reload elimination (queued pass 2 in handover) — DEFERRED -> [[feature-opt-store-reload-elimination]]

Investigated the IR structure (flat post-order array; IR_BLOCK is a no-op range
marker; a driver loop emits statement roots and recurses for operands). The
redundant reload (`mov [slot],rax` then `mov rax,[slot]`) lives DEEP in the
NEXT statement's expression tree, not as an adjacent statement root — so an
IR-stream peephole over roots can't see it. Catching it needs a
"value-in-register" tracker whose invalidation must fire on EVERY rax write,
but rax is written by scattered raw `EmitB` calls throughout ir_codegen.inc with
NO single choke point — airtight invalidation would require auditing hundreds of
sites, and one miss = silent miscompile. Byte-level detection (matching emitted
`Code[]`) is the forbidden path (fixups reference CodeLen). Correct
implementation wants the liveness scaffold flagged for
[[feature-callconv-register-args]] / ticket item 6. Deferred to that scaffold
rather than land a risky tracker (correctness-first). Did the safe queued
peepholes (pass 3 above) instead; branch-over-branch next.

## if-false DCE + strength reduction — MEASURED, REJECTED (2026-07-03)

Measured BEFORE building (const-fold lesson applied):
- **if-false / if-true DCE: 0 fires.** Both Pascal (`if DEBUG` with DEBUG=const
  false) and C (`if(0)`/`if(1)`) fold const `if` conditions at AST time — no
  IR_JUMP_IF_FALSE with a constant condition ever reaches the IR (verified on
  both frontends + the compiler self-compile). Nothing to eliminate.
- **Strength reduction (x*2^k -> shl): 0 fires AND width-unsafe.** Array access
  lowers to IR_INDEX (stride baked in codegen), not an IR_BINOP multiply, so no
  power-of-2 multiply reaches the IR (0 on self-compile). Separately, naive
  mul->shl is NOT value-safe on the current shl path: its <8-byte cdqe fixup
  sign-extends from bit 31, corrupting an offset that overflows 32 bits (imul
  computes the full 64-bit product). Would need a dedicated no-fixup 64-bit shl.

Neither shipped. **Tripwire extended** (IROptWarnMissedFold) to also warn on a
constant-condition IR_JUMP_IF_FALSE, so if a frontend ever stops folding, we
learn and revive if-false DCE. Validated: still silent on real code; the
const-fold arm still fires on injection; -Werror promotes.

## IR const-fold + algebraic identities — MEASURED, REJECTED (2026-07-03)

Implemented both as IR passes, instrumented, measured: **ZERO fires** on the
whole compiler self-compile AND on synthetic foldable tests. PXX eliminates
these upstream — Pascal folds source constants in ConstEval/AST; C + Nil-Python
share the same AN_BINOP lowering; that lowering guards pointer/index stride
`if elemSize > 1` (ir.inc ~3345/3359) so `index*1` is never emitted. No
const-const IR_BINOP nor identity operand ever reaches the IR for any frontend.
Correct but pure dead weight -> NOT shipped (measured-not-speculative, same call
as the rejected allocator bins). A `{ NOTE ... }` in ir.inc records the finding
and the revive condition (a future pass that PRODUCES const-const binops).
Framework (DCE + redundant-jump) unchanged; still v170.

## Progress — shared-IR pass framework + DCE LANDED (2026-07-03)

**Architectural pivot (Rene-endorsed):** optimization now has TWO homes —
emitter-side peepholes (x86-64 only; passes 1-4) and a **shared-IR pass
pipeline** run before codegen, seen by ALL 6 backends and ALL 4 frontends at
once ("optimize prior, not post"). Full study doc:
`devdocs/dev/optimization-architecture.md`.

- **`IROptimize` pipeline** (`ir.inc`), called from `CompileAST` gated
  `OptLevel>=1`, after IRLowerAST+IRVerify, before IREmitMachineCode. Runs
  per procedure body (IRReset per body -> local reasoning, no cross-proc
  boundary). Rewrites IR in place (dead node -> IR_NOP, every backend already
  no-ops it); never touches emitted bytes.
- **IR pass 1 — unreachable-code elimination** (`IROptDeadCode`): code between
  an unconditional transfer (IR_JUMP/IR_TERMINATE/IR_RAISE) and the next
  IR_LABEL is provably unreachable -> NOP. Operand nodes are post-order-adjacent
  before their root (same region) so no live stmt references a dead node.
- **IR pass 2 — redundant jump** (`IROptRedundantJump`): `jmp L; L:` (target is
  the next stmt, skipping NOPs) -> NOP; fall-through reaches L identically.
- **All-target PROVEN**: i386 (cross backend) -O1 code 46807B < -O0 47121B —
  DCE fired via shared IR, identical runtime output. x86-64 -O1 much smaller
  still (also has emitter peepholes 1-4) — illustrates the split cleanly.
- **Gates**: `make test-opt` green (-O1 self-code 3502120->3496244B). `-O0`
  self-host fixedpoint byte-identical (sacred). FULL `make test` under an
  -O1-BUILT compiler: EXIT=0. (Compiler has little dead code, so the
  self-compile delta is small — the FRAMEWORK is the deliverable; DCE/fold/
  identities now plug in here, all-target.)

## Progress — pass 4 LANDED (2026-07-03): compare-into-branch fusion

- **Pass 4 (-O1): compare-into-branch fusion** (x86-64). An `IR_BINOP`
  comparison feeding `IR_JUMP_IF_FALSE` previously emitted
  `cmp; setcc al; movzx eax,al; test rax,rax; jz label` — the boolean was
  materialised only to be immediately tested. Fused to `cmp; j!cc label`:
  evaluate operands into rax/rcx (reusing the -O1 leaf-const / leaf-sym
  direct-load forms), bare `cmp rax,rcx`, then jump on the INVERTED condition
  (branch taken when the comparison is FALSE). ~8 bytes + a setcc/movzx/test
  dropped per if/while/for-guard.
- **Eligibility `CmpFusible`** (ir_codegen.inc, before IREmitMachineCode):
  comparison op {=,<>,<,<=,>,>=} AND neither operand float / AnsiString /
  String / Variant — i.e. exactly the integer/pointer/char/bool/enum ordinal
  compares that lower to the plain `cmp rax,rcx` path. Float (ucomisd) and
  string (dedicated helpers) comparisons fall through to the unchanged generic
  setcc+test+jz path. Inverted jcc opcodes: signed jl/jge/jle/jg (8C/8D/8E/8F)
  + je/jne (84/85), unsigned jb/jae/jbe/ja (82/83/86/87). Label rel32 uses the
  same fixup machinery as the jz path (fixups reference CodeLen — no byte
  rewriting). x86-64-only (the driver loop is; other arches Exit earlier).
- **Gates**: `make test-opt` green (-O1 self-code 3.58MB -> 3.50MB, ~77KB).
  `-O0` self-host fixedpoint byte-identical (sacred gate untouched). FULL
  `make test` under an -O1-BUILT compiler (pass 1-4): EXIT=0.
- **Measured**: -O1-built pass1-4 self-compiles 4.24s vs pass1-3 4.41s
  (~4% faster); ~1.30x vs -O0-built (5.5s). -O1 compiler binary 3.61MB
  (was 3.69MB pass1-3). Speed win in every conditional/loop guard.

## Pin-flip to -O1-built — DONE, v168 (2026-07-03, Rene OK'd)

Pinned binary is now **-O1-built** (`make PXXFLAGS=-O1 stabilize` + `make pin`).
- v168 recorded; pinned binary 3.69MB (was 4.06MB -O0-built), self-code
  code=3579597B. -O1 self-host fixedpoint byte-identical (s4==s5==next).
- FULL `make test` ran with PXXFLAGS=-O1 — every test program compiled at -O1,
  green (broader than the 12-program test-opt corpus).
- Transparency verified on the LIVE pin: `stable_pinned` compiling
  compiler.pas at -O0 = byte-identical to the -O0-built reference output. So
  tracks B/C/D see identical -O0 output, just a ~25% faster / ~9% smaller
  compiler on next pull. Reversible via git.
- `-O0` self-host byte-identity contract itself is unchanged (every pass still
  gates `OptLevel >= 1`); this only changes which binary is blessed, not the
  emission model.

### (prior) Pin-flip readiness note — kept for history

The queued "decide flipping pins to -O1-built" is de-risked and ready:
- **Transparency PROVEN**: an -O1-built compiler emits BYTE-IDENTICAL -O0
  output vs an -O0-built compiler (`cmp` of both compiling compiler.pas at
  -O0 = identical). So flipping the pinned binary is invisible to tracks
  B/C/D — they consume -O0 output, same bytes — while handing them a ~25%
  faster / ~9% smaller compiler. Reversible via git.
- Backed by 3 passes of gates: full `make test` green under an -O1-built
  compiler (each pass), self-host fixedpoint at BOTH -O0 and -O1.
- NOT flipped unilaterally: it changes the shared stable binary every track
  builds on, and Rene was away when asked. It is a one-shot action when he
  OKs it: `make PXXFLAGS=-O1 stabilize` (or rebuild pinned with -O1) + pin +
  push. Until then pins stay -O0-built (v167).

## Branch pass — reassessed (2026-07-03)

Literal "branch-over-branch (`jcc +2; jmp X` -> `j!cc X`)" has NO pervasive
machine-generated source here: integer/float comparisons lower to
`setcc al; movzx eax,al` (already good), not jcc-over-jmp (only one
hand-written spot in the string-compare sequence, ir_codegen.inc ~1340). The
REAL high-frequency branch win is **compare-into-branch fusion**:
`IR_JUMP_IF_FALSE` whose condition is a comparison BINOP currently emits
`cmp; setcc al; movzx eax,al; test rax,rax; jz label` (~8 wasted bytes +
latency every if/loop) — fuse to `cmp; j!cc label` (inverted condition).
Bigger, control-flow / fixup-touching change; gate to integer signed/unsigned
scalar comparisons, fall back to the generic path for float/other. Its own
careful pass (not rushed at a session tail — a half-applied Track A codegen
change trips the self-host gate).

Next passes queued: compare-into-branch fusion (branch pass, above);
inc/dec + imm-fold into BINOP operand; store-reload once the liveness scaffold
([[feature-callconv-register-args]]) lands. Pin-flip awaiting Rene's OK.

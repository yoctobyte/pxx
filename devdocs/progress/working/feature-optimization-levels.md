# Optimization levels (`-O0/-O1/-O2/-O3/-Os`) + pass framework

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20 (design discussion — optimization strategy)
- **Priority:** ~~last~~ **GREENLIT 2026-07-03** (user decision): pin-time is
  now the bottleneck (several minutes per pin; goal ~20s — see
  [[chore-fast-pin-tiered-tests]]), and the language/RTL surface has settled
  enough. Start with the low-hanging -O1 peepholes below.

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

Next passes queued (design above): store-reload elimination (IR-side),
xor-zero / inc-dec / imm-fold peepholes, branch-over-branch. Then DECIDE
flipping pins to -O1-built.

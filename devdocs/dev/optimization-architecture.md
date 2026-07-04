# Optimization architecture (the `-O` arc)

*Study guide to how frankonpiler optimizes. Read alongside the live ticket
`devdocs/progress/working/feature-optimization-levels.md` (per-pass log +
measurements) and the split-out tickets it links.*

This document explains **what we optimize, where each optimization lives, why
it is safe, and how we prove it.** It is written to be read start-to-finish by
someone who did not build it.

---

## 1. Why we optimize (and why only just enough)

PXX is a **single-pass** compiler: it emits straightforward code as it walks
the source, with a naive stack-machine register discipline and no
cross-statement reasoning. That is a feature — it keeps the **self-host
byte-identity gate** tractable (the compiler compiles itself to the exact same
bytes, generation after generation). But it leaves easy cycles on the floor.

The optimization arc was started for **one concrete reason: developer iteration
time.** Re-pinning the compiler (rebuild + self-host verify + tests) had grown
to minutes; a faster compiler shortens every pin. App-level speed is a distant
second — a 2× runtime win is negligible for ~90% of real programs, and the
cross-compile targets (i386/arm32/aarch64/riscv32/xtensa) prioritize
**testable correctness over speed**. So:

> **Priority: x86-64 self-compile speed first and foremost.** Cross targets and
> app speed are bonuses, never the driver. ESP/embedded is already ~10× faster
> than MicroPython; correctness there beats optimization.

Everything below is graded against that: does it make the x86-64 compiler build
itself faster (or smaller, which helps too)?

---

## 2. The `-O` levels and the four hard gates

`-O0..-O3` parse into the global `OptLevel` (`compiler/compiler.pas`,
`defs.inc`). Every optimization is gated `if OptLevel >= <tier>`; **-O0 emits
the historic 1:1 lowering unchanged.**

| Level | Contract |
|-------|----------|
| `-O0` | No optimization beyond the pre-existing local const-fold. 1:1 source↔asm, debuggable. The self-host gate runs here and is **sacred**. |
| `-O1` | Cheap, safe, deterministic, no code-size blow-up. Emitter peepholes + shared-IR DCE/redundant-jump. |
| `-O2` | Fuller speed; size may grow. **Register calling convention (r14/r15) + inline expansion landed (§4).** Pins are -O2-built. |
| `-O3` | Aggressive, opt-in. **Inline slice 2b (straight-line multi-statement bodies) landed here** — gated -O3 so the -O2 pin stays untouched until 2b is proven. Reserved also for nested/non-leaf inline + cost model. |

### Level-assignment policy (the O1 / O2 line)

`-O` level is **not** graded by "how sure am I it's correct" — correctness is a
gate at *every* level (gate 3 below); a pass that can miscompile is a bug, not an
`-O2` feature. Level is graded by **risk/payoff and provability**:

- **`-O1` = provably safe.** Exact transforms with a decidable correctness
  argument, no heuristic, no cost model, no code growth, and **no unproven
  invariant**. If a pass's correctness rests on an assumption, that assumption
  must be *airtight and documented* (e.g. DCE's "every landing site is an
  IR_LABEL", §4) — the moment it could silently break, the pass is no longer
  `-O1`.
- **`-O2` = experimental / side-effecting / heuristic.** Anything that may not
  always pay (cost-model-driven inlining, unrolling), grows code, changes the
  ABI (register calling convention), or relies on analysis that could be
  unsound in a corner (aliasing, liveness) lives here — behind the flag, opt-in,
  benchmark-gated.

Concretely: DCE and redundant-jump are `-O1` because their correctness is a
*proof over today's IR* (no computed jumps exist). A **latent** hazard — e.g.
a future jump-table `case` lowering that would break DCE's landing-site
invariant — is flagged with guard-rail comments at both the pass
(`IROptDeadCode`) and the likely introduction site (`AN_CASE` lowering) so
adding one trips review. That is how an `-O1` pass stays honestly `-O1`.

**The four gates every pass must pass** (non-negotiable, from the ticket):

1. **Determinism.** No heuristic may depend on pointer values, allocation
   addresses, or hash iteration order — those break self-host fixedpoint. Cost
   models count IR nodes (stable), never anything address-derived.
2. **Self-host byte-identical at every shipped level.** The compiler
   self-compiles to identical bytes at `-O0` *and* at `-O1`
   (`-O1` fixedpoint: an -O1-built compiler rebuilds itself at -O1 to
   byte-identity). `make test-opt` runs both.
3. **Cross-level output oracle.** The same program compiled `-O0` vs `-O1`
   must produce **identical runtime output**. Any behavioural difference = an
   optimizer bug, caught immediately. `make test-opt`'s differential corpus.
4. **`-O0` stays 1:1.** Never sneak a fold/motion into -O0. The sacred gate.

There is a fifth, forward-looking rule in the ticket: **volatile before
optimizing** — MMIO/hardware memory accesses must be marked volatile before any
dead-store / redundant-load elimination is allowed to touch memory ops. Not
yet relevant (no memory-elision pass has landed).

---

## 3. The two families: where an optimization can live

This is the central design fact. An optimization lives in exactly one of two
places, and **which one determines how many targets and languages it helps.**

### 3a. Shared-IR passes — all targets, all frontends

The compiler lowers every frontend (Pascal, C, Nil-Python, `.asm`) to **one
shared IR** (a flat post-order array of nodes: `IRKind[]/IRA[]/IRB[]/IRC[]/
IRIVal[]/IRTk[]`, indices `0..IRCount-1`). Each backend
(`ir_codegen.inc` = x86-64, plus `ir_codegen386/arm32/aarch64/riscv32/
xtensa.inc`) reads that same array.

An optimization done as an **IR-to-IR transform, before codegen**, is therefore
seen by *every* backend and produced-for by *every* frontend automatically —
**one implementation, six targets, four languages, one self-host gate.** This
is the architecturally-preferred home ("optimize prior, not post"). It is
where dead-code elimination, constant folding, and algebraic identities belong.

The pipeline entry point is **`IROptimize`** in `compiler/ir.inc`, called from
`CompileAST` (`ir_codegen.inc`) gated `if OptLevel >= 1`, **after** `IRLowerAST`
+ `IRVerify` and **before** `IREmitMachineCode`:

```
CompileAST(node):
  IRReset; IRLowerAST(node); IRVerify;
  if OptLevel >= 1 then IROptimize;      <-- shared, all-target, all-frontend
  if DumpIR then IRDump;                 (--dump-ir shows the OPTIMIZED IR)
  IREmitMachineCode;                     dispatches to the per-target backend
```

`CompileAST` runs **once per procedure body** (`IRReset` clears the array each
call), so every IR pass reasons over a single self-contained body — reachability
and jump-adjacency are local, no cross-procedure boundary to special-case.

Passes rewrite the IR **in place**: a removed node becomes `IR_NOP` (every
backend already emits nothing for it) and a redundant jump is turned into
`IR_NOP`. **No pass ever rewrites emitted machine bytes** — branch/label fixups
store absolute `CodeLen` offsets and moving bytes would corrupt them. That rule
(from the -O plumbing work) is why elimination happens at the IR level, before
any byte is emitted.

### 3b. Emitter-side peepholes — x86-64 only

Some wins are inherently about the **x86-64 register contract or instruction
encoding** and cannot be expressed as target-independent IR without
reimplementing a register model each backend would duplicate anyway. These live
directly in the x86-64 emitter and help **only x86-64** — which, per §1, is the
priority target, so that is an acceptable and deliberate trade, not a
limitation to fix.

The dividing line, concretely:

> If the win is "this computation/branch is redundant" → **IR pass** (§3a),
> all-target. If the win is "this value belongs directly in *this register* /
> this constant has a shorter *encoding*" → **emitter peephole** (§3b),
> x86-64.

---

## 4. What has landed (with before/after and the safety argument)

### Emitter-side peepholes (x86-64 only, §3b)

**Pass 1 — leaf-const BINOP operand direct load** (`ir_codegen.inc`, `IR_BINOP`).
A constant right operand loads straight into `rcx` instead of the stack dance:
```
push rax ; <eval right> ; mov rcx,rax ; pop rax     ->     mov rcx, imm32/imm64
```
Safe: the constant has no side effects; downstream register contract (rax=left,
rcx=right) is byte-identical.

**Pass 2 — leaf-sym BINOP operand direct load** (`ir_codegen.inc` + `EmitLoadVarRcx`
in `symtab.inc`). Extends pass 1 to a side-effect-free scalar local/param/global
right operand: it loads directly into `rcx` (`EmitLoadVarRcx` mirrors
`EmitLoadVar`'s scalar branch with the reg field switched rax→rcx). Guard
`LeafSymRcxLoadable` admits only non-float, non-string, non-array,
non-by-ref scalars. Safe: a plain load has no side effects, so evaluating it
after the left is order-safe; the direct-rcx target avoids clobbering the left
in rax. (Cannot reorder right-first — an arbitrary left expression could clobber
rcx.)

**Pass 3 — constant-load size peephole** (`emit.inc`, `MovRaxImm` — the single
x86-64 const→rax choke point). Shrinks the fixed 10-byte `movabs rax, imm64`:
`v=0`→`xor eax,eax` (2B); `0..2^32-1`→`mov eax,imm32` (5B, zero-extends);
`-2^31..-1`→`mov rax,imm32` (7B, sign-extends). Safe: every consumer only needs
rax=v; all three encodings extend to the full register. Mostly a size win, and
size is pervasive here (constant loads are everywhere).

**Pass 4 — compare-into-branch fusion** (`ir_codegen.inc`, `IR_JUMP_IF_FALSE` +
`CmpFusible`). A comparison feeding a conditional branch used to materialise a
boolean only to test it:
```
cmp rax,rcx ; setcc al ; movzx eax,al ; test rax,rax ; jz L    ->    cmp rax,rcx ; j!cc L
```
The label branches on the **inverted** condition (taken when the comparison is
false). `CmpFusible` gates to `{=,<>,<,<=,>,>=}` on integer/pointer/char/bool/
enum operands — exactly the plain `cmp rax,rcx` path; float (ucomisd) and
string (dedicated helpers) fall through to the unchanged generic path. The
label rel32 uses the same fixup machinery as the old `jz` (no byte rewriting).
*This one is conceptually IR-level and is a future candidate to relocate into
§3a as an IR tag so cross targets get it too.*

### Shared-IR passes (all targets, all frontends, §3a)

**IR pass 1 — unreachable-code elimination** (`ir.inc`, `IROptDeadCode`). Walks
the body tracking reachability. Code between an unconditional transfer
(`IR_JUMP`/`IR_TERMINATE`/`IR_RAISE` — exit/return, goto/break/continue, raise)
and the next `IR_LABEL` owns no label, so nothing can jump into it and the
transfer blocks fall-through → **provably unreachable** → `IR_NOP`. Any label is
a potential jump target, so it makes the code after it reachable again. Safety
argument: operand/value nodes are post-order-adjacent *before* their statement
root, inside the same reachability region as the root, so a live statement never
references a node stranded in a dead region.

**IR pass 2 — redundant jump elimination** (`ir.inc`, `IROptRedundantJump`).
Drops `jmp L; L:` — an unconditional jump whose target label is the very next
statement (skipping `IR_NOP`s, e.g. code pass 1 just killed). Falling through
reaches `L` identically. Common in if/loop lowering (a then-branch tail jump
over an absent else).

Demonstrated all-target: a program with dead-after-`continue` code compiled for
**i386** shrinks at `-O1` vs `-O0` (DCE fired on the cross backend via the
shared IR), with identical runtime output.

### The `-O2` tier (landed 2026-07-04)

`-O2` is no longer an alias of `-O1`. Two features landed, both gated
`OptLevel >= 2` so `-O0`/`-O1` stay byte-identical:

**Register calling convention — r14/r15 param residency** (x86-64 only;
`feature-callconv-register-args`). Up to 2 eligible scalar-by-value params per
body are parked in the callee-saved registers r14/r15 for the whole routine, so
reads become `mov rax/rcx, r14/r15` instead of a per-use frame reload. The frame
slot stays authoritative (the early prologue spill writes it; every store
dual-writes it via `RegcallRefreshResident`), so the register is a *read cache* —
any non-`EmitLoadVar` reader and the excluded addr-taken cases stay correct, and
callee-saved regs survive calls by ABI so there is no cross-call spill.
Eligibility (`RegcallAssignResidency`, `ir_codegen.inc`): scalar int/ptr, not
`IsRef`/`IsArray`, address never taken in-body (no `IR_LEA`/`IR_SLOTADDR` on the
SymIdx), no inline asm, not a generator/stackless routine. Caller r14/r15 saved
to a reserved frame slot at body entry, restored in every `EmitProcEpilog` path.
`--measure-regcall` (phase 0) sized it: 79% of params eligible, 61% captured by
2 registers. Measured **1.34× self-compile, code −12%** — same emitted output.

**Inline routine expansion** (all targets — AST/IR level, NOT target-gated;
`feature-inline-routines`). A leaf function whose body is a single `Result := E`
pure expression, or an `if C then Result:=A else Result:=B` one-liner (retained
as an `AN_TERNARY`), over scalar-by-value params is spliced in place of a direct
call. The single-pass obstacle (callee body torn down after its `CompileAST`) is
solved by *retaining* the eligible body in a reserved top slice of the AST pool
`[INLINE_AST_BASE..MAX_AST)` — never touched by the per-proc reset — with param
idents rewritten to `AN_INLINE_PARAM(i)` placeholders (`TryRetainInlineBody`,
`parser.inc`). At the `AN_CALL` site (`IRInlineExpand`, `ir.inc`) the retained
body is cloned into the live pool with placeholders bound to the args and lowered
normally. Pure args (literal / plain scalar ident) substitute directly; if any
arg has a side effect, ALL args are captured left-to-right into temps first, so
Pascal evaluation order holds. Auto-inline: keys on eligibility, not the `inline;`
keyword (also captured). `--measure-inline` (phase 0) sized it: 664 leaf@12
call sites (2.2%), on hot tiny helpers. Validated byte-identical `-O0` vs `-O2`
across **505 programs** and on all four cross targets (i386/aarch64/arm32/
riscv32).

**Slice 2b (straight-line multi-statement bodies, `-O3`).** A leaf function whose
body is a straight-line statement sequence with scalar ordinal locals and a
single Result (`t := a+b; Result := t*t`) is retained as the whole `AN_SEQ` chain
(param/local/Result idents → `AN_INLINE_PARAM`/`AN_INLINE_LOCAL`/`AN_INLINE_RESULT`
placeholders) and spliced by allocating a fresh caller local per callee local + a
Result temp, cloning + lowering the statements, then yielding a load of the Result
temp (the same emit-inline-then-load pattern `AN_TERNARY` uses). Straight-line
only, all locals scalar, Result never read, a read-before-write guard, slice-3 arg
temps. **Gated `-O3`** so the `-O2` pin is untouched (an -O2 build emits
byte-identical output to the pinned binary). Validated O0==O3 across 500 programs
+ all four cross targets; -O3 self-fixedpoint. **Nested (non-leaf) inline stays
deferred** (a later -O3+ slice).

All proven by the same four gates plus per-tier self-fixedpoint (`-O2` and now
`-O3`). **Pins are `-O2`-built** (transparent: an -O2 compiler emits the same
`-O0` output, so downstream sees identical bytes, just a faster compiler); `-O3`
is opt-in on top.

---

## 5. What is queued, and why it is where it is

| Work | Home | Status | Note |
|------|------|--------|------|
| IR const-fold (`const OP const`) | IR (§3a) | **rejected — measured 0 fires** | PXX pre-folds upstream (ConstEval/AST); no const-const IR_BINOP reaches the IR for any frontend. Revive only if a future pass PRODUCES const-const binops. |
| IR algebraic identities (`x*1`,`x+0`…) | IR (§3a) | **rejected — measured 0 fires** | lowering guards stride `if elemSize>1` (no `x*1`), source identities pre-simplified. Value-dropping forms (`x*0`) deliberately never attempted (side-effect hazard). |
| DCE of `if false` / const-true | IR (§3a) | **rejected — measured 0 fires** | Pascal AND C fold const `if` conditions at AST time (verified: `if DEBUG`, C `if(0)` → 0 const-condition IR_JUMP_IF_FALSE reaches IR). Tripwired. |
| Strength reduction (`x*2^k→shl`) | IR (§3a) | **rejected — 0 fires + width-unsafe** | array access uses IR_INDEX (no IR_BINOP multiply); and the shl path's <8-byte cdqe fixup corrupts offsets that overflow 32 bits, so mul→shl is not value-safe there. Would need a no-fixup 64-bit shl. |
| Relocate compare-fusion to an IR tag | IR (§3a) | idea | would give cross targets pass 4 |
| imm-fold into BINOP (`add rax,imm32`) | emitter (§3b) | queued | x86-64, cheap |
| inc/dec, rel8 short branches | emitter (§3b) | queued | x86-64, size |
| **Store-reload elimination** | IR, needs liveness | **blocked** | `feature-opt-store-reload-elimination` — no rax-write choke point for airtight invalidation; wants the liveness scaffold |
| **Register calling convention (r14/r15)** | ABI (x86-64) | **LANDED (-O2, §4)** | `feature-callconv-register-args` phase 1. Phase 2 (rbx/r12/r13) + phase 3 (caller-side) queued; diminishing per measurement. |
| **Inline expansion (pure-expr + ternary leaf)** | AST/IR (all targets) | **LANDED (-O2, §4)** | `feature-inline-routines` v1/2a/3. |
| **Inline slice 2b (straight-line multi-stmt bodies)** | AST/IR (all targets) | **LANDED (-O3, §4)** | opt-in until proven; nested/non-leaf still deferred. |

Store-reload elimination remains the notable blocked item — it wants the same
register-liveness scaffold, and phase-2 regcall would build toward it.

---

## 6. Methodology — how every pass is proven

Per-pass rhythm (never skip a step; slow steps run as separate visible
commands):

1. **Implement**, gated `OptLevel >= tier`.
2. **`make test-opt`** — differential corpus (each program compiled -O0/-O1/-O2/
   -O3, runtime output `cmp`'d against -O0) + the -O1/-O2/-O3 self-compile
   fixedpoints.
3. **`-O0` self-host fixedpoint** — `pxx` compiles the compiler, that result
   compiles the compiler, `cmp` byte-identical. The sacred gate.
4. **Full `make test` under an -O1-BUILT compiler** — swap in a compiler that
   was itself built at -O1 (its own machine code went through the passes), run
   the whole suite. Catches a pass miscompiling the compiler.
5. **`hyperfine`** the self-compile (warmup ≥2, runs ≥5); record the delta in
   the ticket log.
6. **Commit** small, one pass per commit.
7. **Stabilize + pin.** Pins are now **-O2-built** (proven transparent: an
   -O2-built compiler emits byte-identical -O0 output, so tracks B/C/D see no
   change, just a faster compiler). `make PXXFLAGS=-O2 stabilize` rebuilds the
   compiler at -O2, runs the full suite at -O2, records the -O2 binary; `make
   pin` blesses it. (`-O3` is opt-in, not pinned — slice 2b lives there until
   proven.)

**Benchmark harness:** `make benchmark-opt-levels` builds the compiler at each
`-O` tier, asserts every tier emits identical (correct) output, reports each
tier binary's size, and hyperfines each tier self-compiling. `-O3` still tracks
`-O2` (aliases it until a nested-inline / higher-tier pass lands).

**Cumulative result so far:** the `-O1`-built x86-64 compiler self-compiles
~1.30× faster than `-O0`-built and is ~11% smaller; `-O2` (regcall + inline, §4)
adds the register-residency win on top (≈1.34× vs `-O0` measured for regcall
alone). Numbers per pass live in the ticket logs. `-O0` output is byte-identical
across all tiers (the sacred gate).

---

## 7. Map — file by file

| File | What it holds |
|------|---------------|
| `compiler/compiler.pas` | `-O` flag parse → `OptLevel`; `--measure-regcall`/`--measure-inline` probes |
| `compiler/defs.inc` | `OptLevel` global; IR opcode + `AN_*` constants; `AN_INLINE_PARAM`, `INLINE_AST_BASE`, `RcResident*`, `Inline*` globals |
| `compiler/ir.inc` | shared IR build; **`IROptimize` pipeline + IR passes (§3a)**; **inline splice `IRInlineExpand`/`IRCloneInlineBody` (§4)** |
| `compiler/ir_codegen.inc` | x86-64 backend; `CompileAST` (pipeline call site); emitter passes 1/2/4; `CmpFusible`; **`RegcallAssignResidency` (§4)** |
| `compiler/parser.inc` | **inline retention `TryRetainInlineBody`/`CloneToInlineRegion`/`BuildInlineTernary` (§4)**; `inline;` directive capture |
| `compiler/emit.inc` | low-level x86-64 emit; `MovRaxImm` (pass 3) |
| `compiler/symtab.inc` | `EmitLoadVar`/`EmitLoadVarRcx` + `LeafSymRcxLoadable` (pass 2); **`ResidentRegOf`/`RegcallRefreshResident` + resident hooks + epilogue restore (§4)** |
| `compiler/ir_codegen386/arm32/aarch64/riscv32/xtensa.inc` | cross backends — read the shared (optimized) IR incl. inlined bodies; **no emitter peepholes, no regcall (x86-64 only)** |
| `Makefile` | `test-opt` (-O1/-O2 differential corpus + fixedpoints); cross-target inline gates; `stabilize`/`pin` (now -O2); `benchmark-opt-levels` |

**Tickets:** `feature-optimization-levels` (umbrella + log),
`feature-callconv-register-args` (-O2 regcall — phase 0/1 done),
`feature-opt-store-reload-elimination` (blocked),
`feature-inline-routines` (-O2 inlining — v1/2a/3 done, 2b/nested queued),
`feature-const-eval-typecast-int64` (a fold gap).

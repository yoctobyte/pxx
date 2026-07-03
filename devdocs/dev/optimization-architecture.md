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
| `-O1` | Cheap, safe, deterministic, no code-size blow-up. Everything landed so far is `-O1`. |
| `-O2` | Fuller speed; size may grow. **Currently aliases -O1** (no -O2-only pass exists yet). Reserved for register calling convention + inlining. |
| `-O3` | Aggressive, benchmark-gated. Currently aliases -O1. |

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

---

## 5. What is queued, and why it is where it is

| Work | Home | Status | Note |
|------|------|--------|------|
| Complete const folding (`Int64()` cast) | IR (§3a) | queued | all-target; `feature-const-eval-typecast-int64` |
| Algebraic identities (`x*1`,`x+0`,`x*2→shl`) | IR (§3a) | queued | all-target |
| DCE of `if false` / const-true branches | IR (§3a) | queued | needs const-condition detection |
| Relocate compare-fusion to an IR tag | IR (§3a) | idea | would give cross targets pass 4 |
| imm-fold into BINOP (`add rax,imm32`) | emitter (§3b) | queued | x86-64, cheap |
| inc/dec, rel8 short branches | emitter (§3b) | queued | x86-64, size |
| **Store-reload elimination** | IR, needs liveness | **blocked** | `feature-opt-store-reload-elimination` — no rax-write choke point for airtight invalidation; wants the liveness scaffold |
| **Register calling convention** | ABI flag-day (§3b-wide) | **not started** | `feature-callconv-register-args` (-O2). The single biggest self-compile win — FPC's ~2× lead is mostly this. Own arc. |

The **register calling convention** is the real prize for developer iteration
and is deliberately deferred until the IR-pass framework (this doc's §3a) and a
register-liveness scaffold exist, so it plugs in cleanly rather than as a
one-off.

---

## 6. Methodology — how every pass is proven

Per-pass rhythm (never skip a step; slow steps run as separate visible
commands):

1. **Implement**, gated `OptLevel >= tier`.
2. **`make test-opt`** — differential corpus (each program compiled -O0 and -O1,
   runtime output `cmp`'d) + the `-O1` self-compile fixedpoint.
3. **`-O0` self-host fixedpoint** — `pxx` compiles the compiler, that result
   compiles the compiler, `cmp` byte-identical. The sacred gate.
4. **Full `make test` under an -O1-BUILT compiler** — swap in a compiler that
   was itself built at -O1 (its own machine code went through the passes), run
   the whole suite. Catches a pass miscompiling the compiler.
5. **`hyperfine`** the self-compile (warmup ≥2, runs ≥5); record the delta in
   the ticket log.
6. **Commit** small, one pass per commit.
7. **Stabilize + pin.** Pins are now **-O1-built** (proven transparent: an
   -O1-built compiler emits byte-identical -O0 output, so tracks B/C/D see no
   change, just a faster/smaller compiler). `make PXXFLAGS=-O1 stabilize`
   rebuilds the compiler at -O1, runs the full suite at -O1, records the -O1
   binary; `make pin` blesses it.

**Benchmark harness:** `make benchmark-opt-levels` builds the compiler at each
`-O` tier, asserts every tier emits identical (correct) output, reports each
tier binary's size, and hyperfines each tier self-compiling. `-O2`/`-O3` rows
currently track `-O1` (they alias it until a higher-tier pass lands).

**Cumulative result so far:** the `-O1`-built x86-64 compiler self-compiles
~1.30× faster than `-O0`-built (≈4.2s vs 5.5s) and is ~11% smaller
(≈3.6MB vs 4.06MB). Numbers per pass live in the ticket log.

---

## 7. Map — file by file

| File | What it holds |
|------|---------------|
| `compiler/compiler.pas` | `-O` flag parse → `OptLevel` |
| `compiler/defs.inc` | `OptLevel` global; IR opcode constants |
| `compiler/ir.inc` | shared IR build; **`IROptimize` pipeline + IR passes (§3a)** |
| `compiler/ir_codegen.inc` | x86-64 backend; `CompileAST` (pipeline call site); emitter passes 1/2/4; `CmpFusible` |
| `compiler/emit.inc` | low-level x86-64 emit; `MovRaxImm` (pass 3) |
| `compiler/symtab.inc` | `EmitLoadVar`/`EmitLoadVarRcx` + `LeafSymRcxLoadable` (pass 2) |
| `compiler/ir_codegen386/arm32/aarch64/riscv32/xtensa.inc` | cross backends — read the shared (optimized) IR; **no emitter peepholes** |
| `Makefile` | `test-opt`, `stabilize`/`pin`, `benchmark-opt-levels` |

**Tickets:** `feature-optimization-levels` (umbrella + log),
`feature-callconv-register-args` (-O2 regcall),
`feature-opt-store-reload-elimination` (blocked),
`feature-inline-routines` (-O1/-O2 inlining),
`feature-const-eval-typecast-int64` (a fold gap).

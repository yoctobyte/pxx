---
track: A
prio: 50
type: feature
blocked-by: []
summary: "pxx has no riscv64 target at all — only riscv32, which exists for ESP-class bare metal. Real RISC-V hardware (notebooks, SBCs) is RV64GC running Linux, so today we cannot build for the machines RISC-V actually ships on. The harness is already ready: run_target.sh handles riscv64, install_qemu.sh installs qemu-riscv64, twatch_web lists it in CROSS_TARGETS — nothing can produce a binary for it."
status: working
owner: claude-A
---

# riscv64 as a hosted, first-class target

**Filed 2026-08-19 at the user's prompting:** RISC-V *"is a serious platform… these days there
are notebooks with a riscv processor — it's here to stay."* Today the only RISC-V support we
have is **riscv32, shaped by ESP-class bare metal**, which is not the thing RISC-V hardware
actually ships as.

## Measured

**The compiler knows no riscv64.** `compiler/defs.inc` target mentions: x86-64 (32),
xtensa (11), riscv32 (8), i386 (8), aarch64 (7), arm32 (5). Backend files:
`ir_codegen386` / `_aarch64` / `_arm32` / `_riscv32` / `_xtensa`. **No `ir_codegen_riscv64`.**

**But the harness already expects it**, which is the striking part:

    tools/run_target.sh:8      # arch: x86_64 | i386 | aarch64 | arm32 | riscv32 | riscv64
    tools/run_target.sh:78-80  riscv64) need qemu-riscv64; exec qemu-riscv64 "$bin" "$@"
    tools/install_qemu.sh:24   installs qemu-riscv64
    tools/twatch_web.py:89     CROSS_TARGETS = (..., "riscv32", "riscv64", ...)

**So we can already RUN riscv64 binaries and cannot PRODUCE one.** Side finding worth
checking separately: `twatch_web`'s `CROSS_TARGETS` lists a target that can never be built,
so the dashboard may be carrying a column that is structurally empty rather than failing —
an empty column reads as "no news", not as "impossible".

## Why riscv32 is not this ticket

RV32 and RV64 differ in XLEN — register width, pointer size, and the whole set of `*W`
instructions. Our riscv32 additionally carries **bare-metal assumptions from the ESP work**
and a substantial open-bug list (softfloat subnormals, atomics, byval record params, nested
dynamic arrays, `SetLength` on a string array element, hosted `writeln` hanging, chess-perft
runtime corruption). **Those bugs are riscv32's; they are not automatically riscv64's, and
riscv64 must not be filed behind them.**

## The first question — it decides the size of the job

**Is riscv64 a widening of `ir_codegen_riscv32.inc` (XLEN as a parameter) or a new backend?**
Measure before estimating. RV64 is RV32 with wider registers plus the `W` instruction family,
so a parameterised backend is plausible — but so is the answer that riscv32's bare-metal
assumptions are woven through it deeply enough that sharing costs more than it saves. **This
is the one thing to establish first**, and it is a measurement, not a judgement call.

Useful precedent: we already have both a 32-bit and a 64-bit backend in two other families
(i386/x86-64, arm32/aarch64). **How those two pairs were split — shared or separate — is the
cheapest available evidence** for what to do here.

## Why it is worth doing

- **It is where RISC-V actually is.** Hosted RV64GC Linux is what SBCs and the first notebooks
  run. An MCU-only RISC-V story misses the platform the user is pointing at.
- **A real milestone is reachable: self-hosting on riscv64.** The compiler is written in
  Pascal, so a hosted riscv64 backend plus the Pascal frontend means pxx could compile itself
  natively on RISC-V hardware. That is a much stronger statement than "we cross-compile to it".
- **It composes with
  [[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]** — "a Python
  compiler for RISC-V, reduced" is exactly the use case that ticket is for.

## Honest scoping

The user has **ESP hardware only** right now, so riscv64 would initially be verified under
qemu — which `run_target.sh` already does for every other cross target, so this is normal
rather than a compromise. Real-hardware validation waits for hardware, and that is fine;
qemu-verified is the same bar every other cross target currently meets.

## Gate

Track A's: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`, plus the riscv64
cross tests under qemu once the target exists. Track T sweeps the matrix — note it already
has a `riscv64` slot waiting in `CROSS_TARGETS`.

## Log
- 2026-08-19 — filed. Prio 50 as a strategic target rather than an urgent one; the user may
  well rank it higher, and the "here to stay" framing suggests it should not sit at the
  bottom for long.

## 2026-08-21 — the first question, ANSWERED by measurement

The ticket says the widen-vs-fork question *"decides the size of the job"* and is
*"a measurement, not a judgement call"*. Measured. The answer is **widen**, and
two of the ticket's own premises did not survive.

### The precedent points one way, and it is the wrong way

Both existing 32/64 pairs are **entirely separate backends**: `ir_codegen_arm32`
and `ir_codegen_aarch64` share **zero** emitter helper names, and so do
`ir_codegen386` and `ir_codegen`. Cheapest available evidence, as the ticket
said — and it does not transfer, for a reason that is itself measurable:
**those pairs are different instruction sets.** aarch64 is not wide arm32; it is
a new encoding. RV32 and RV64 are the *same* ISA with XLEN as a parameter.

### What the numbers say

| | |
| --- | --- |
| `ir_codegen_riscv32.inc` | **3441 lines** — the smallest hosted backend we have |
| `rv32enc.inc` (pure encoders) | **208 lines**, and RV64's base encodings are the *same bits* |
| `rv32_*` calls inside the backend | **778**, of which **260** are the width-sensitive `lw`/`sw` |
| `rv32_*` calls **outside** the backend | **140**, across five files |

That last row is the finding that decides it. `rv32_*` is not contained in the
backend: `symtab.inc` (47), `cparser.inc` (37), `exception_emit.inc` (31),
`pasparser_proc.inc` (17), `pasparser_prog.inc` (8) — and **87 of those 140 are
`lw`/`sw`**, i.e. exactly the width-sensitive ones. Forking the backend would
leave every one of those five files still needing an XLEN-aware path, so the fork
buys a duplicated 3441-line file and solves none of the actual problem.

### The two premises that did not survive

**"riscv32 carries bare-metal assumptions from the ESP work woven through it."**
It does not. The whole backend contains **one** `EspBareBoot` reference and five
occurrences of the word "bare". The ESP coupling lives in `compiler.pas`,
`elfwriter.inc`, `pasparser_prog.inc` and friends — the driver and the image
writer — not in codegen. So riscv32 is a *clean* base to widen, which is the
opposite of the ticket's expectation.

**"riscv32's open bug list must not block riscv64."** Right conclusion, but the
reasoning changes: if the backend is shared, most of those bugs become *shared*
too. That is an argument in favour, not against — fixing softfloat subnormals or
byval record params once fixes both — but it must be stated, because "riscv64 is
not blocked by riscv32's bugs" stops being automatically true the moment the file
is shared. The bugs that are genuinely riscv32's are the bare-metal ones.

### Shape of the work, in order

1. **`rv32enc.inc` → `rvenc.inc`**, additively. RV64 needs ~15 encoders the file
   does not have: `ld`/`sd` (funct3 3), and the `W` family (`addw`/`addiw`/`subw`/
   `sllw`/`srlw`/`sraw`/`mulw`/`divw`/`remw`, opcodes `$3B`/`$1B`). Everything
   else is bit-identical.
   **One real correctness trap, already located:** `rv32_slli`/`srli`/`srai` mask
   the shift amount to **5 bits** (`sh and $1F`). RV64 shifts take **6**
   (`and $3F`), and the extra bit sits where RV32 puts part of `funct7` — so a
   shift by 32..63 would silently encode as a *different instruction*. Exactly
   the plausible-wrong-value shape this repo keeps paying for.
2. **XLEN-parameterised load/store helpers** (`rv_lx`/`rv_sx`, picking `lw`/`sw`
   or `ld`/`sd` from `TARGET_PTR_SIZE`), then convert the pointer-width call
   sites mechanically — 260 in the backend, 87 outside. The rest of the 918 calls
   are width-neutral.
3. Register width, ABI (LP64 vs ILP32), the `elfwriter` machine/class fields.
4. **Hardware float is a separate slice, and bigger than it looks.**
   `rv32enc.inc` has **zero** F/D encoders — riscv32 is softfloat throughout.
   RV64**GC** has hardware double, so a first-class hosted target wants the whole
   F/D instruction set plus its ABI. Do NOT fold this into the widening; land
   riscv64-with-softfloat first, hardware float second.

### Side finding CONFIRMED, and filed

The ticket flagged it as worth checking separately, and it is real:
`tools/twatch_web.py:89` lists `riscv64` in `CROSS_TARGETS` while the test
manager mentions it **nowhere** — so the dashboard carries a column that cannot
ever be built. An empty column reads as "no news", not as "impossible". Filed as
[[bug-t-twatch-web-lists-a-target-that-cannot-be-built]] (Track T's file, not
mine to fix).

### Status

The question the ticket asks first is answered; the implementation is a
multi-session job and is not started. Back to `backlog` with the plan above
rather than held in a lock nobody is working.

---

## The first question, measured (2026-08-21)

The ticket says the one thing to establish first is **widening vs new backend**,
and that it is a measurement rather than a judgement. Here is the measurement.

### 1. The cheapest evidence: how the other two 32/64 pairs were split

Both were split into **separate backends**, and not narrowly:

| family | 32-bit | 64-bit |
| --- | --- | --- |
| x86 | `ir_codegen386.inc`, 5063 lines | inside `ir_codegen.inc` (the default backend) |
| arm | `ir_codegen_arm32.inc`, 4409 lines | `ir_codegen_aarch64.inc`, 3906 lines |
| riscv | `ir_codegen_riscv32.inc`, 3561 lines | — |

That precedent is weaker than it looks for arm (A32 and A64 are different
instruction encodings, so there was never a choice) but it is **not** weak for
x86: i386 and x86-64 share an encoding family the way RV32 and RV64 do, and they
were still split. Which raises the useful question — split on account of *what*?

### 2. What actually differs: the register-pair layer, and it is deletion

Every 32-bit backend carries an isomorphic Int64-as-register-**pair** layer, and
no 64-bit backend has one at all:

```
i386      Is64Bit386      EmitNode64_386    EmitBinop64_386    EmitUDivMod64Core_386  EmitIDivMod64Core_386
arm32     Is64BitArm32    EmitNode64Arm32   EmitBinop64Arm32   EmitUDivMod64Arm32     EmitIDivMod64Arm32
riscv32   Is64BitRISCV32  EmitNode64RISCV32 EmitBinop64RISCV32 EmitUDivMod64RISCV32   EmitIDivMod64RISCV32
```

In `ir_codegen_riscv32.inc` that is **lines 423-863 — 441 lines — plus 36 call
sites** spread through the node emitter. On RV64 an `Int64` is one register, so
every one of those disappears.

**This is the finding that decides it.** The difference between RV32 and RV64
codegen is not a width constant to thread through; it is 441 lines and 36 call
sites that must be *absent*. Parameterising means keeping both paths alive under
an XLEN test — a second path through every binop, divmod, load and store, taken
only on one target. That is exactly the shape
`devdocs/dev/normalise-dont-special-case.md` calls the path that stays broken,
and it is why both existing pairs split.

### 3. What is genuinely shared: the encoder, and it is small

`rv32enc.inc` is **208 lines, 44 mnemonic encoders** plus six field packers
(`EmitRType`/`IType`/`SType`/`BType`/`UType`/`JType`). RV64I keeps every RV32I
base encoding unchanged, so **41 of the 44 are shared verbatim**.

The three that are not are a warning, not a detail:

```pascal
procedure rv32_slli(rd, rs1, sh: Integer);  begin EmitIType(sh and $1F, rs1, 1, rd, $13); end;
procedure rv32_srli(rd, rs1, sh: Integer);  begin EmitIType(sh and $1F, rs1, 5, rd, $13); end;
procedure rv32_srai(rd, rs1, sh: Integer);  begin EmitIType((sh and $1F) or $400, rs1, 5, rd, $13); end;
```

RV64 shifts take a **6-bit** shamt. Reusing these as-is silently truncates any
shift of 32..63 — a wrong VALUE far from the cause, the failure mode this repo
pays most for. So the encoder is shared, but the shift encoders get explicit
RV64 siblings rather than a widened common one; a blind `and $3F` would make the
RV32 side accept a shift it cannot encode.

RV64 then ADDS: `ld` / `sd` / `lwu`, and the W family (`addw` `subw` `sllw`
`srlw` `sraw` `addiw` `slliw` `srliw` `sraiw` `mulw` `divw` `divuw` `remw`
`remuw`) — none of which exist on RV32, so they are pure addition, not a change.

### 4. The ticket's worry about ESP contamination does not hold up

`ir_codegen_riscv32.inc` has **15** ESP/bare-metal mentions in 3561 lines, and
the substantive ones are few and localised: the `EspBareBoot` boot path
(mtvec + `esp_intr_alloc`), the atomics capability check (`SocCoreCount > 1`
with no A extension is refused), and two "ESP has no managed records yet" skips.
Bare metal is **not** woven through this backend; it is a handful of guards. The
hypothesis in the section above ("riscv32's bare-metal assumptions are woven
through it deeply enough that sharing costs more than it saves") was worth
stating and is measurably false — the reason to split is item 2, not this.

### 5. The frontend is already parameterised

`TARGET_PTR_SIZE` is a runtime `Integer` in `defs.inc`, already consulted by
`cparser.inc`, `ast_syminfer.inc` and `rtti_emit.inc`. The ILP32/LP64 split above
the backend therefore costs a value, not a port.

### 6. The plumbing cost is smaller than the site count suggests

105 `TARGET_RISCV32` sites across 17 files — but **21 of them are one predicate
written out inline**:

```pascal
(TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot))
```

(20 in `pasparser_prog.inc`, 1 in `pasparser_proc.inc`.) That is "is this target
hosted?" spelled out 21 times, and adding ANY new target means editing all 21 or
getting a silently wrong answer at whichever one is missed. Factoring it into a
`TargetIsHosted` function is a prerequisite for this ticket, not a nicety — and
it belongs to [[meta-constant-normalisation]], which is already ranked at p45.
Doing it first makes riscv64 (and the target after it) nearly free at those
sites.

For scale: `TARGET_AARCH64`, the last 64-bit target added, has 73 sites.

## Decision

**A new backend, `ir_codegen_riscv64.inc`, over a shared encoder layer.** Not a
widening of `ir_codegen_riscv32.inc`.

- Shared: `rv32enc.inc`'s six field packers and 41 of its 44 encoders, unchanged.
- Explicitly not shared: the three shift encoders (5-bit vs 6-bit shamt — a
  silent wrong value if merged), plus RV64's `ld`/`sd`/`lwu` and the W family as
  additions.
- Not carried over at all: the 441-line register-pair layer and its 36 call
  sites. On RV64 they are not parameterised, they are gone.

This is the same answer both existing 32/64 pairs reached, for the same reason,
and it keeps riscv32's open bug list off riscv64's back — which the ticket
explicitly asks for.

## Sequencing

1. `TargetIsHosted` (the 21 inline copies) — [[meta-constant-normalisation]]'s
   lane, and a prerequisite here.
2. Encoder layer: RV64 shift/`ld`/`sd`/`lwu`/W encoders alongside the RV32 ones.
3. `ir_codegen_riscv64.inc` + `TARGET_RISCV64` + `--target=riscv64` + ELFCLASS64
   with `e_machine` 243 (the value riscv32 already writes — it is XLEN-agnostic;
   the class byte is what differs).
4. Verification is functional, under `qemu-riscv64`, which **is installed on
   this box** — there is no local riscv assembler, so the byte-exact-against-`as`
   method used for other encoders is unavailable and running the code is the
   oracle. `tools/run_target.sh riscv64` already works.

Nothing above is blocked. Step 1 is separable and lands on its own.

---
track: A
prio: 10
type: feature
blocked-by: []
summary: "pxx has no riscv64 target at all — only riscv32, which exists for ESP-class bare metal. Real RISC-V hardware (notebooks, SBCs) is RV64GC running Linux, so today we cannot build for the machines RISC-V actually ships on. The harness is already ready: run_target.sh handles riscv64, install_qemu.sh installs qemu-riscv64, twatch_web lists it in CROSS_TARGETS — nothing can produce a binary for it."
status: rainy-day
owner: ""
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

---

## Step 1 landed: `TargetIsEspClass`, and the hazard list it revealed

`compiler/util.inc` now carries

```pascal
function TargetIsEspClass: Boolean;
begin
  Result := (TargetArch = TARGET_XTENSA) or
            ((TargetArch = TARGET_RISCV32) and EspBareBoot);
end;
```

replacing all 21 hand-written copies (20 `pasparser_prog.inc`, 1
`pasparser_proc.inc`). Verified as a pure refactor, not just by reading: the
pre-change and post-change compilers were both built from source and made to
emit the same programs for seven target configurations — native, i386, arm32,
aarch64, hosted riscv32, bare riscv32, xtensa — **byte-identical output on every
one that compiles, identical refusal on every one that does not.** (De Morgan
makes it provable too, but the repo's rule is measure, not reason.)

### The 13 sites deliberately NOT folded in

There is a second spelling, `(TargetArch = TARGET_XTENSA) or (TargetArch =
TARGET_RISCV32)` with **no** profile test. It looks like the same concept and is
at least four different ones, so a shared predicate would assert a sameness that
is not there. Each needs its own answer before riscv64 is added — and two of
them are already wrong for *hosted riscv32*, today, without riscv64 in the
picture:

| site | what it really means | riscv64 answer | status |
| --- | --- | --- | --- |
| `emit.inc:106` (EmitDataRef) | "pointer is 4 bytes" — the disjunction is i386/arm32/xtensa/riscv32 | **NO** (8-byte ref) | should be `TARGET_PTR_SIZE = 4`, which already exists as a runtime var |
| `pasparser_prog.inc:124` (float pulls heap) | same "32-bit target" concept | **NO** | same normalisation |
| `pasparser_decl.inc:133`, `:271` | "no hardware double" → `Real = Single` | **NO** | **wrong for hosted riscv32 today** — [[bug-a-real-is-single-on-hosted-riscv32]] |
| `emit.inc:149` (EmitwriteSyscall) | "bare metal, no write(2)" — but tests the arch, not the profile, and silently `Exit`s | **NO** | dead for riscv32 in practice (only the 386/arm32/aarch64/x64 backends call it) but it is a silent no-op wearing a bare-metal comment |
| `emit.inc:219` (EmitMmapArena) | "bare metal, no mmap" — same mis-keying, but Errors rather than no-ops | **NO** | loud, so harmless; still mis-keyed |
| `exception_emit.inc:425` | "windowed ABI, no longjmp unwind" | **NO** | **unreachable for riscv32** — the real arm is at `:317` ("hosted AND ESP bare"), earlier in the same `else if` chain |
| `elfwriter.inc:1829` | no DWARF `-g` | probably NO (riscv64 hosted should get `-g`) | |
| `elfwriter.inc:2306` | the only two `--emit-obj` targets | NO | |
| `lexer.inc:727` | ESP-IDF heap (already profile-qualified with `not EspBareBoot`) | NO | correct as written |
| `pasparser_prog.inc:608`, `:655` | RTL pulls, unqualified variant of the 21 | NO | check against `TargetIsEspClass` |
| `emit.inc:251`, `pasparser_prog.inc:643` | xtensa-only | N/A | |

**The pattern is one mistake made repeatedly: `TARGET_RISCV32` used as a proxy
for "small, bare, soft-float, no OS".** That was true when riscv32 existed only
for the ESP32-C3 and stopped being true when it became dual-role. riscv64
inherits nothing from those sites, so the port must add itself to each one
consciously — which is exactly why they are listed rather than collapsed.

`e_machine` is worth one line of its own: `elfwriter.inc` writes **243** for
riscv32 (`:1955`, `:2063`, `:2326`), and 243 is `EM_RISCV`, which is
XLEN-agnostic. riscv64 reuses it unchanged; what differs is the ELF **class**
byte and the 64-bit header/section layout, i.e. `writeELF` vs `writeELF32`.

### Remaining sequence

2. Encoder layer: RV64 `ld`/`sd`/`lwu`, the W family, and 6-bit-shamt shift
   encoders as siblings (not a widening — see the decision above).
3. `ir_codegen_riscv64.inc` + `TARGET_RISCV64` + `--target=riscv64` + ELFCLASS64.
4. Functional verification under `qemu-riscv64` (installed here; no local riscv
   assembler exists, so running the code is the oracle).

## Parked back to backlog, with the scoping done (2026-08-21)

Step 1 (`TargetIsEspClass`) **landed green and complete** — there is no
half-applied compiler change here, which is why this returns to `backlog/`
rather than `unfinished/`: nothing is in flight, the remaining work is simply
not started.

What stopped it from going further in one session is worth recording, because it
kills the obvious decomposition:

**There is no "minimal backend" increment.** The plan was to land the plumbing
plus just enough codegen for `program p; begin Halt(7); end.`, verify it under
qemu-riscv64, and then fill in nodes one testable increment at a time. That does
not work: the smallest possible program pulls **116 procs** of RTL on x86-64 and
**152** on riscv32 (measured), because builtinheap and friends come in
unconditionally. So the RTL's own bodies must codegen before *anything* links,
and the first runnable riscv64 binary needs a substantially complete
`ir_codegen_riscv64.inc` — string ops, heap, memmove, calls, the lot. Roughly
the 3120 non-pair lines of `ir_codegen_riscv32.inc`, transformed.

That makes step 3 a single multi-hour unit of work rather than a series of
green ones, and it should be picked up when there is room for it in one go.
Everything it needs is decided and written down above: the split decision, the
encoder inventory, the 13-site hazard table, and the verification method
(functional, under qemu-riscv64, which is installed).

Two riscv32 bugs were found *because* of this scoping and are already fixed or
filed — both instances of the same mis-keying the hazard table describes:

- [[bug-a-halt-n-exits-zero-on-hosted-riscv32]] — **fixed**, all five targets
  now agree with FPC. Found because `Halt(n)` was going to be how the first
  riscv64 increment proved itself.
- [[bug-a-real-is-single-on-hosted-riscv32]] — filed, needs the `Real = Double`
  call.

Next actor: start at "Remaining sequence" step 2 above.


---

## DEFERRED to rainy-day (user, 2026-08-21)

> *"nice idea, totally deferred for rainy days"*

Three reasons, all of which are about cost rather than merit — the target itself
is still wanted:

1. **No native hardware.** Verification would be qemu-only, and qemu is a model,
   not a machine. Every result would carry that caveat.
2. **Serious development time.** A multi-session job by its own scoping, and the
   shape question below is not even settled yet.
3. **It would slow Track T gating further.** Another cross target in the matrix
   costs every sweep, permanently, for a target nobody can run natively.

Also answers [[decide-riscv64-vs-the-bug-queue-for-autonomous-nights]]: an
autonomous Track A night keeps clearing the bug queue. This ticket is out of the
ranked queues entirely now, so the nightly skip is no longer a silent decision.

## STILL OPEN when unparked: the two write-ups above CONTRADICT each other

Do not read this ticket as having settled its own first question. It contains two
analyses from 2026-08-21 that reach **opposite** answers, and both are still here:

| write-up | answer | evidence |
| --- | --- | --- |
| *"the first question, ANSWERED by measurement"* | **widen** `ir_codegen_riscv32.inc` | 140 `rv32_*` emitter calls live OUTSIDE the backend — symtab 47, cparser 37, exception_emit 31, pasparser_proc 17, pasparser_prog 8 — and **87 are the width-sensitive `lw`/`sw`**. A fork "buys a duplicated 3441-line file and solves none of the actual problem". Explicitly rejects the arm32/aarch64 precedent: those are different ISAs, RV32/RV64 are one ISA with XLEN as a parameter |
| *"Decision"* | **a new `ir_codegen_riscv64.inc`**, sharing the encoder layer | the register-pair layer is deletion not parameterisation; the shift encoders differ (5- vs 6-bit shamt) and merging them is a silent wrong value; cites the arm32/aarch64 precedent as "the same answer both existing 32/64 pairs reached" |

**The second does not answer the first.** Its section 6 counts `TARGET_RISCV32`
*predicate* sites (105 across 17 files) — a different metric from the 140 `rv32_*`
*emitter* calls. Under a separate backend those 140 sites still emit RV32
instructions and still need an XLEN answer. That is write-up 1's whole argument
and it is unaddressed.

Resolving it is cheap next to implementing the wrong shape: one person reading
those 140 call sites. **Do that first when this is unparked.**

## Two things that are NOT parked with this

- **[[meta-constant-normalisation]] stays ranked (p45).** `TargetIsHosted` — the
  same predicate written out inline 21 times, where adding any new target means
  editing all 21 or getting a silently wrong answer at whichever is missed — is
  worth doing for its own sake. It was listed here as a prerequisite; it is not a
  riscv64 dependency, riscv64 is just one beneficiary.
- **The testability gap is worth closing cheaply whenever.** `qemu-riscv32` and
  `qemu-riscv64` are both installed and `tools/run_target.sh riscv64` already
  works, but there is **no riscv assembler and no riscv gcc** on the box — so the
  byte-exact-against-`as` check used for other encoders is unavailable and there
  is no gcc differential oracle. A `riscv64-linux-gnu-binutils` install buys the
  byte-exact check back for the price of a package, and would apply to riscv32
  today.

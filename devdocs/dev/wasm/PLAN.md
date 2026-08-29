# wasm32 target — development plan

Branch `wasm`, standalone checkout `~/frankwasm`. Rules of the lane:
[`CHARTER.md`](CHARTER.md). Measured accounting behind every number here:
[`../wasm-target-findings.md`](../wasm-target-findings.md) (on `master`).
Board entry: `feature-target-wasm`, claimed into `working/` (a live lock — it is
not dispatchable, which is deliberate).

## Decisions locked in the 2026-08-27 scoping session

These are settled. Re-open one only with a reason, and file a `decide-*` if the
reason is a judgment call rather than a measurement.

| decision | value | why |
| --- | --- | --- |
| baseline | MVP + sign-ext + mutable-globals + bulk-memory + multi-value | all universally shipped since ~2021 |
| memory | **memory32**, not memory64 | memory64 is not universally shipped; 4GB is plenty |
| system interface | **WASI preview1** only | preview2 / component model is a moving target |
| browser | a second *import profile*, not WASI | the browser case is our own import set |
| binary emission | direct, from `wasmenc.inc` | peer of `x64enc.inc`; never shell out to `wat2wasm` |
| text form | `asmtext_wasm.inc` emits WAT | peer of the five existing `asmtext_*.inc` |
| WAT labels | **named** (`$L12`), never numeric `br` depths | `br 3` is unreadable, and readability is half the point |
| locals | **all frame slots in linear memory** (shadow stack); wasm locals are scratch only | makes `IR_LEA`/`IR_SLOTADDR`, `var` params, records and `absolute` overlays work unchanged |
| control flow v1 | one `loop` + `block` chain + `br_table` on a label variable | handles every CFG including irreducible; relooper later as an `-O` pass |
| exceptions v1 | pending-flag threading | no engine proposal, no version dependency, and it composes with `br_table` dispatch |
| EH proposal | **not** in v1 | the legacy-vs-final opcode split is live fragmentation |
| nil safety | reserve page 0; explicit nil checks under `-g` | address 0 is *valid* linear memory — `nil^` does not trap |
| shadow stack | explicit limit check in the prologue under `-g` | no guard page; it would run into the heap silently |

## Phase 0 — prep (COMPLETE; Phase 1 waits only on the registration skeleton)

An earlier version of this plan blocked all wasm work on a target-property
refactor. **That was wrong and the block is lifted.** `TARGET_PTR_SIZE` already
exists (`defs.inc:1758`, 129 call sites) and a wasm32 target declares its
pointer width at the `compiler.pas:1508` arm like every other target.

- [x] **Does anything need `IR_PROCADDR` values to be comparable or
      arithmetic-able?** No — and this was the one answer that could have
      reshaped the call phase (then numbered 4, now 5). Grepped `lib/`,
      `examples/`, `compiler/`: the only code
      treating a procedure address as a number is `lib/rtl/scheduler.pas`
      (`Int64(@CoStart)` into a hand-built stack frame, four times, one per
      arch). Nothing orders procvars; nothing does arithmetic on one. That
      consumer is the coroutine stack-frame builder — already out of scope for
      wasm. **Table indices are viable**, with index 0 reserved as the null
      function reference.
- [x] **Enumerate the chains a 7th target falls through.** Three confirmed:
      `exception_emit.inc:8` (6 arms), `coroutine_emit.inc:25` (4 arms) — both
      emit *nothing at all*, no diagnostic — and `lexer.inc:936` (no CPU
      defines). Handed to the two Track A tickets. Caveat recorded there: the
      scan missed `lexer.inc` because it sits inside an outer
      `if TargetArch <> TARGET_X86_64` guard, so it is a starting point, not an
      inventory.
- [x] **Stand up the tooling.** Done 2026-08-27 — and the box was already
      equipped. `wabt 1.0.36` (`wat2wasm`, `wasm-validate`, `wasm2wat`) and
      `node v22.22.1` are installed; **`wasmtime` is not**, but node is a
      complete runtime for Phases 1-5 and `node:wasi` covers preview1 for
      Phase 8. Install wasmtime before Phase 8 as the reference standalone
      runtime; nothing before that needs it.

      A hand-written probe was validated and run end to end, deliberately
      exercising the two mechanisms this plan rests on:

      | mechanism | phase it de-risks | result |
      | --- | --- | --- |
      | spill a value to linear memory and read it back (`i32.store`/`i32.load`) | Phase 2 shadow stack | `addmul(3,4) = 14` |
      | `block` / `loop` / `br_if` | Phase 3 dispatch | `loopsum(10) = 45` |

      Chain: `wat2wasm` -> `wasm-validate` -> `wasm2wat` round-trip ->
      `new WebAssembly.Instance` under node. All four steps clean. **Phase 1 has
      its oracle.**

### The gate on Phase 1 — and why it is a feature, not a delay

**Phase 1 does not start until
`feature-a-wasm32-target-registration-skeleton` has landed on `master`.**

That ticket registers `TARGET_WASM32` across the 9 shared files a new target
touches (~270 lines, measured from `bd49a59535c3`) with **no codegen** — every
dispatch chain gets an explicit `Error('wasm32: not implemented')`.

This is the whole conflict-avoidance strategy in one move. Registration is the
only part of this work that lives in files other lanes edit constantly. Land it
on `master` first and **the branch touches no shared files at all** — a claim
made here as a prediction and, as of 2026-08-28, one that has held through five
phases. Let the branch do the registration instead and every `master` merge
conflicts in exactly the hottest files in the tree.

**So the standing rule for this branch: if a phase needs a shared-file edit,
that is a signal to file a Track A ticket and wait — never to make the edit
here.** Two were predicted: the call phase (VMT fixups) and exceptions. **The
first one turned out not to exist** — scoped 2026-08-28, see Phase 5, where the
predicted patch site is correct for ELF and irrelevant to a target that never
calls `elfwriter`. That leaves exceptions as the only one still expected, and
it should be scoped the same way before it is believed. Anything else appearing
on that list is a surprise worth stopping for.

**PHASE NUMBERS SHIFTED TWICE ON 2026-08-28**, both times because a phase that
every program needs had been scheduled behind phases that are merely unusual.
The data segment took the Phase 4 slot; the heap took Phase 6, ahead of
exceptions, having previously been one line inside the PAL phase. Everything
after each insertion moved up. Text elsewhere in this file that predates a
shift has been updated where it points FORWARD; where it records what a past
session measured or decided it is left alone, because rewriting a record
falsifies it.

**If it happens a third time, stop renumbering and fix the ordering rule
instead.** Both shifts have the same cause and the rule is already written down
in Phase 6: this plan was ordered by what wasm makes *different*, and the real
order is set by what every program *needs*.

## Phase 1 — module writer + WAT emitter, no codegen

`wasmenc.inc` and `asmtext_wasm.inc`, exercised by a hand-built module — type,
function, memory, export, code sections, LEB128, a body that returns a constant.

- **Milestone:** `pxx` emits a `.wasm` that `wasm-validate` accepts and
  `wasmtime` runs, and a `.wat` that `wasm2wat` round-trips to the same thing.
- **Why first:** it is the only phase with a complete external oracle. Every
  later phase debugs *through* this one, so it must be beyond suspicion.

## Phase 2 — straight-line codegen

The ~50 mechanical IR ops. Shadow stack established: a frame pointer in a wasm
global, all slots in linear memory, `i32.load`/`i32.store` where the register
backends use `[rbp-N]`. Model on `ir_codegen_riscv32.inc` (3,891 lines) — same
32-bit shape, and wasm locals make it *easier* (infinite typed registers, no
allocator, no spills).

- **~~Milestone: a program with arithmetic, records and arrays, no control
  flow, produces the same value as its native build.~~ Known-unreachable,
  rewritten 2026-08-28.** It assumed a program could be compiled in isolation.
  It cannot. Every `.pas` pulls `compiler/builtin/builtinheap.pas`
  unconditionally (`-dPXX_NODEFAULTRTL` does not suppress it), and those bodies
  use `IR_STORE_MEM`, calls and control flow. The backend's first ever run
  stopped in builtinheap, not in the test program. "Implement the ops my test
  needs" was never reachable; "implement the ops the builtins need" is most of
  Phases 2-4 at once.
- **Milestones are now properties of the COVERAGE REPORT**, because `5 of 125`
  is a real metric and "Phase 2 complete" is not. `WasmReportCoverage` prints
  before every module is written:

  ```
  wasm32: 5 of 125 bodies lowered; 120 emitted as `unreachable` (Phase 2 is incomplete):
      PXXHdrInit — non-i32 parameter base
  ```

  Each stubbed body cites the *first* thing that stopped it, so the report is a
  worklist ordered by what is actually blocking, not by what the plan guessed.

  | phase | milestone, stated as a property of that report |
  | --- | --- |
  | **2 — values and slots** | no entry cites a *value* op **other than a call**, a non-scalar slot, or a non-scalar signature. Scalar i32/i64/f64 loads, stores, consts, binops, unaries, slot and pointer access all lower. |
  | **3 — control flow** | no entry cites a control-flow op (`IR_JUMP`, `IR_JUMP_IF_FALSE`, `IR_LABEL` reachability). The `br_table` dispatch exists. |
  | **4 — calls and code addresses** | no entry cites `IR_CALL`, `IR_VIRTUAL_CALL` or `IR_CALL_IND`; the report reads **N of N** for the builtin set. |

  Two corrections to that table, both from running it (2026-08-28):

  * **Phase 2's row said "no value op", which cannot be satisfied before Phase
    4.** A call in value position is a value op *and* an `IR_CALL`, so the two
    rows overlapped and Phase 2 could never close on its own wording. Amended
    above to carve calls out. Phase 2's real content is: every value op that is
    not a call, and every SCALAR slot and signature.
  * **"non-i32" became "non-scalar".** The row was written when the backend
    lowered i32 only, and phrasing the milestone as the absence of the
    *then-current* refusal message baked a limitation into the target it was
    measuring. Reaching it meant deleting the refusal, not satisfying it. What
    Phase 2 actually owes is that the four wasm value types all work; what it
    does not owe is aggregates — a record or set parameter has no wasm value
    type at all and goes by pointer, which is an ABI question and therefore
    the call phase's (Phase 5).

  A milestone stated as "the report no longer says X" is only as good as X, and
  X here was a message this lane wrote about itself. Prefer stating what must
  WORK; keep the report as the evidence, not as the definition.

  **The differential is unchanged and still the real gate**: `check_phase2.sh`
  diffs the lowered bodies against the native build. Coverage says how much is
  lowered; the differential says whether it is *right*. Neither substitutes for
  the other, and a rising counter with a failing diff is worse than no counter.
- **Design done 2026-08-27, ahead of the phase:**
  [`phase2-shadow-stack.md`](phase2-shadow-stack.md). It corrects the
  model-on-riscv32 advice above, which is right about the frame and **wrong
  about the values**: `Is64Bit*` is a *backend* function, so the IR hands the
  backend `tyInt64` intact and wasm32 uses native `i64`/`f64` where every other
  32-bit target this project has had was forced into register pairs and
  soft-float. wasm32 is a 4-byte-pointer target with native 64-bit arithmetic —
  a combination none of the six existing targets has. That deletes riscv32's
  hardest ~480 lines (lines 436-915: the lo:hi model, the 64-iteration
  restoring long division, the 128-bit checked multiply, the sltu carry
  synthesis) rather than porting them. Frame/addressing → riscv32; value model
  → x86-64/aarch64.
- Also settled there: expression temporaries live on **wasm's operand stack**,
  not the shadow stack (the backends' push/pop dance is deleted, not
  translated); the shadow stack holds named slots only. And `IR_FRAME` Errors at
  lowering like xtensa rather than link a chain nothing can walk — recorded as a
  **target limitation**, not a `decide-*`: `defs.inc` already settled the
  identical case, so this is derivation. It becomes a decision only when a real
  program calling `get_frame` must work here, with that program named.

## Phase 3 — control flow — **DONE 2026-08-28**

The `br_table` dispatch loop; the 5 control-flow IR ops.

- **Milestone:** `if`/`while`/`for`/`case`/`goto` all correct, *and* no coverage
  entry cites a control-flow op. This is where the differential probe starts
  earning its keep.
- **Met.** Coverage 41 → 66 of 147 bodies, no control-flow op left in the
  report, and `test/wasm/check_phase3.sh` diffs 26 values against the native
  build: nested if/else, while, repeat/until, `for` in both directions, `case`
  with a value / a list / a range / an else, break, continue, short-circuit
  and/or, a loop inside a loop, early `Exit`, and `goto`. Construction and the
  two properties that make it work (fallthrough is free; a stale `$pc` is never
  read) are documented in `ir_codegen_wasm32.inc`'s control-flow section.
- **The differential is not a formality for this phase specifically.** A
  dispatch bug — a block index off by one, a branch depth counted from the
  wrong nesting — produces a module that VALIDATES and runs the wrong code.
  `wasm-validate` has nothing to say about any of them. That is the same
  boundary CHARTER.md now records: the validator makes the *width* class
  unrepresentable, not the *meaning* class.
- **The `goto` case is in the slice on purpose.** Every other form has the
  reducible CFG the frontend built; `goto` has whatever the programmer wrote,
  and it is the one form the milestone names that would otherwise have been
  claimed without evidence.
- **Known cap, measured 2026-08-27:** the layout costs one nested `block` per
  basic block, and `wat2wasm` (wabt 1.0.36) SIGSEGVs at ~9000 nesting while V8
  accepts 9015 without complaint. The engine is not the limit; wabt's recursive
  text parser is. Binary emission is unaffected — only the WAT debug oracle is
  capped, exactly where a big function makes you want it. Details and the two
  mitigations in [`phase5-exceptions.md`](phase5-exceptions.md).

## Phase 4 — the initialised blob — **DONE 2026-08-28**

`Data[]` — string literals, typed consts, VMT and RTTI blobs — reaches the
module as one active data segment.

**This phase was not in the plan, and its absence was a plan defect worth
naming.** Phase 5's milestone below is virtual dispatch; VMTs live in `Data[]`;
nothing was emitting those bytes at all. "Resolve VMT slots to table indices"
presupposes the slots exist, so the milestone was unsatisfiable before this
phase existed — **a milestone that presupposes unbuilt scaffolding is the same
failure as one defined by the absence of a symptom** (the trap Phase 2's note
records). Both are unreachable in a way that only shows up when you try to
satisfy them. This one was found by scoping; the next would have been found by
being blocked.

- **Milestone:** a typed const reads back under wasm what it reads natively.
  Met — `test/wasm/check_data.sh`, 18 values.
- **Layout.** BSS keeps its fixed base at 1024, unchanged; the blob follows it,
  and a data-resident global goes through a new immutable `$data` global. Both
  region sizes are still growing while bodies are emitted, so whichever region
  sits second cannot have its base written as an `i32.const` where the
  reference is emitted. One of the two costs an indirection and it should be
  the rare one: every global variable is a BSS reference, only a typed const is
  a blob reference. The alternative — a padded 5-byte LEB placeholder patched
  at write time, as the ELF writers patch code — is faster and worse here,
  because the WAT is generated alongside the bytes and a patched constant is
  invisible in a text stream already written.
- **`DATA_SYM_BIAS` is decoded here for the first time** (`defs.inc:1682`).
  Missing it computes an address near `0x20000400`, which traps — the good
  failure mode, and still a failure, arriving the first time a program declares
  a typed const array.
- **The program body arrives in PIECES**, and this is the one place a wasm
  module cannot mirror a register target for free. A frontend emits top-level
  code with `CurProc = -1` more than once — every typed const built by startup
  code emits its stores as another such call. On a register target those land
  in `Code[]` one after another and *are* one function. Here they became N
  functions all named `main`, none of them called: it surfaced as
  `duplicate export "main"`, a complaint about the symptom, while the defect
  was that the bodies were unreachable and every global they initialise read
  zero. Each chunk now keeps its own slot and `main` is synthesised as a call
  to each in order.
- **The typed const that forced it is a Track A ticket, not a wasm bug:**
  [[bug-a-a-typed-const-record-is-built-by-startup-code-not-stored-as-data]] —
  the sibling the array fix did not reach. 116 bytes of code per 16-byte record
  against zero code for an Integer array of the same total size.
- **The WAT oracle now runs on every slice** (`test/wasm/wat_oracle.sh`). It had
  run on one hand-built four-function module for four phases and passed, and it
  was hiding two bugs that both need more than four functions to show: a
  local-name lookup keyed to "the most recently declared function", and an
  export order that followed function order in the text and insertion order in
  the binary. Only the TEXT module was ever wrong, which is why it survived —
  the binary encodes indices and never asks for a name, so the `.wasm`
  validated, ran, and matched the native build while the `.wat` named locals it
  never declared.

## Phase 5 — calls through a table — **DONE 2026-08-28** (virtual dispatch emits, does not yet run)

Table section + element section + `call_indirect` with type indices. VMT slots
and RTTI method entries resolve to **table indices**.

**The shared-file escape this plan predicted at `elfwriter.inc:1937` does not
exist.** That patch site is correct for ELF and irrelevant here, because wasm
never calls `elfwriter`. Scoped 2026-08-28; five things had to be true and each
was checked rather than inferred from the first:

- `AddMethodFix(dataPos, procIdx)` (`emit.inc:103`) is the **one** append point,
  and it records a *relocation*, not an address: "the 8-byte slot at
  `Data[dataPos]` names `Procs[procIdx]`". Target-independent by construction —
  a code address does not exist when `Data[]` is built. wasm consumes the same
  list at write time and writes a table index where `elfwriter` writes
  `entry + BodyAddr`. Sole-appender confirmed by grepping the ARRAY and the
  COUNT, not the call sites: `Inc(MethodFixCount)` appears once in the tree.
- `ProcAddrFix` (`@proc` in code) is recorded **per-backend**, in each
  `ir_codegen_*.inc`'s `IR_PROCADDR` arm. Ours lives in our file.
- The VMT slot stride is `*8` on **every** target already, decided and
  documented at `ir.inc:7332`, address in the low dword, with the three 32-bit
  backends doing a 4-byte indirect read of it. wasm32 has `PtrSize = 4`, so an
  `IR_LOAD` at `[vmt + slot*8]` already reads exactly the four bytes we write
  the index into. No layout change.
- `AN_CLASS_VIRTUAL_CALL` and interface dispatch already lower to loads +
  `IR_CALL_IND` in shared `ir.inc` (5130, 11676, 11750) with no backend op.
- DCE is already off for wasm32 (`dce.inc:224`), so its `MethodFixups` /
  `ProcAddrFix` roots and `CodePos` compaction never run here.

`Procs[].BodyAddr` was the other loose end and it is closed the same way: of its
111 mentions, every one resolves to a frontend writing `CodeLen`, `EmitCallProc`'s
per-arch rel-branch math (register backends only), DWARF (`-g`, not wired), the
ELF writer, DCE, the x64 disassembler, or two cosmetic printers. Nothing reads it
as an address on any path wasm32 takes.

- **File list: `ir_codegen_wasm32.inc` and `wasmenc.inc`.** Both ours. No grant,
  nothing to sequence.
- **Shape:** the three missing sections (table id 4, element id 9) plus the
  `call_indirect` opcode ($11); one function `WasmTableIndex(procIdx)` as the
  single place a proc becomes an index, called by both the `IR_PROCADDR` arm and
  the `MethodFixups` loop so the two cannot disagree; the element segment lists
  every proc whose address is taken (`MethodFixups` ∪ `ProcAddrFix`) with index
  0 reserved null, so a nil procvar traps on call and needs no separate check.
- **Milestone:** virtual dispatch, interfaces, procedural variables.
  **Half met, and the half is the point.** Procedural variables run and are
  diffed against the native build — `test/wasm/check_calls.sh`, 7 values: a
  procvar in a global, one chosen at run time, one passed as an argument and
  called by the callee, two functions through one parameter, and a nil procvar
  through `Assigned`. **Virtual dispatch is written, emits, and validates, and
  cannot be RUN**: every path to a virtual call starts with a class
  instantiation, which is a heap allocation. `virtual_slice.pas` — three
  levels, an override at each, dispatch through the base type, a non-virtual
  method calling two virtual ones on `Self`, `inherited`, and a virtual call in
  a loop over an array of different classes — is compiled and validated by the
  check, which says in as many words that it does not prove dispatch. A check
  that goes green while proving less than it looks like is what this suite
  exists to avoid.
- **So the HEAP gates this phase's milestone**, the way the data segment gated
  the last one — the same finding twice, and worth stating as a pattern rather
  than as two incidents: **the ordering in this plan was derived from what wasm
  makes DIFFERENT, and the real order is set by what every program NEEDS.**
  Nothing runs without allocation.
- **`gate.sh quick` ran ONCE at the end of this phase** as the **falsification
  of the scoping claim above** — not as a gate on the work — and the scoping
  claim **held**: GREEN, the six targets did not move, because nothing shared
  was edited.
  **The run found something else, and that is the better argument for it.** The
  FPC seed canary was RED, and had been for several commits: pxx accepts a call
  to a routine defined later in the same include and FPC does not, so
  `ir_codegen_wasm32.inc` broke *bootstrapping* the day direct calls landed
  while self-hosting perfectly. Nothing in the per-fix loop can see it —
  `make compiler/pascal26` compiles with pxx. Fixed with forwards (`cd878f9ca`),
  verified by building `compiler.pas` with `fpc` directly. **Run this gate once
  per phase**: a narrow loop is blind by construction, and what it is blind to
  is not what you were looking for.

### Where the phase ended: 121 of 126, and what the last five are

**Final measurement at `cc0680a08`**, `writeln(42)`:

| body | blocker |
| --- | --- |
| `PXXVarBinOp`, `PXXVarNot` | assignment of a **frozen string** to a slot |
| `IInterface.QueryInterface` / `._AddRef` / `._Release` | declared without a body — **not a defect, and never will be** |

So the honest count is **two**, and the honest statement is not "two bodies
left" but **"frozen strings are read-only on wasm32"**. Reading works —
`PXXWriteFrozenW` takes a literal's blob whole, and the data slice has covered
const strings since Phase 4 — but `s: string[15]; s := 'hello'` refuses with
*"slot s has no wasm value type"*. The variant engine's two bodies are the
RTL's instance of that gap, not a tail-end cleanup, and chasing them
individually would have been wasted work.

That statement exists because the REFUSAL was fixed first. It read
`value of type 4 in assignment to ` — an enum ordinal to go look up, and a name
that had vanished because the destination is a compiler temporary. A message is
read precisely when nobody has the enum in front of them. It now names the type
and says `an unnamed temporary (symbol 144)`, and that is what turned two
mystery bodies into a measured property of the target.

`IR_STORE_SYM` of a `tyString` is the work: on x86-64 it is three cases
(char→string, AnsiString→frozen, frozen→frozen) with capacity clamping. It is
phase-sized, it is needed for every `string[N]`, `ShortString` and record string
field — not just for variants — and it is the natural next phase.

### What the blocker histogram said about the ORDER of this phase

**Re-measured at `3f99f2034`** against `w0.pas` (`writeln(42)`), 17 unlowered of
126 — and the interesting part is not the count, it is that **six bodies changed
what they BLAME**. The RTL error reporters used to report `IR_WRITE`; they now
report `Halt`, because the write lowered and the next thing in the way became
visible. A blocker histogram measures the *topmost* obstacle, so a phase's real
yield is partly invisible in the total:

| blocker | count | who |
| --- | --- | --- |
| `Halt` — needs the WASI `proc_exit` import | **7** | the six RTL error reporters plus `PXXExitProcess`. Cheap now: the import mechanism exists. |
| `value IR op 2` | 2 | `PXXVarBinOp`, `PXXVarNot` — the variant engine |
| `IR_SLOTADDR` (op 50) | 3 | `PxxSciDigits17`, `PxxIntDDigits`, `PxxFracDigits` |
| non-integer constant (float literals) | 2 | `PXXWriteFloatFixed`, `PXXWriteFloatSci` |
| declared without an implementation | 3 | `IInterface`'s three methods — **not a defect** |

Three of the seventeen are the `IInterface` declarations, which will never have
bodies. So the real remaining surface is **fourteen bodies across four
mechanisms**, and one of the four is now a two-line import.

The earlier measurement, at `f2c0ca849` against `phase4_slice.pas`, 22 unlowered
bodies:

| blocker | count | who |
| --- | --- | --- |
| `IR_CALL_IND` | **9** | 8 are RTL error hooks calling an installed procvar handler — `PXXDivZero`, `PXXOverflow`, `PXXRangeError`, `PXXNilRef`, `PXXInvalidCast`, `PXXVariantError`, `PXXObjRelease` — plus the two interface refcount helpers. **Not user procvars.** |
| `IR_VIRTUAL_CALL` | **1** | `TInterfacedObject._Release`. One, in the whole RTL. |
| `IR_WRITE` + `IR_SLOTADDR` | 5 + 2 | all seven in the float writers |
| heap / `Halt` | 5 | Phase 6 |

**The plan's assumption that this phase is where virtual dispatch matters is off
by an order of magnitude.** The indirect-call table is worth nine bodies, the
VMT path one — and the VMT path falls out of the same mechanism for free.

## Phase 6 — the heap and the host — **BOTH MILESTONES MET 2026-08-28** (the heap runs on a bad arena; see below)

`PXXAlloc` and its siblings: the builtin lowerings spelled as a NEGATIVE proc
index on `IR_CALL` (`-Ord(tkGetMem)` and friends), plus `memory.grow` as the
only way linear memory gets bigger.

**Why this moved.** It was not a phase at all — it was one line inside the PAL
phase ("heap growth goes through `memory.grow`, not `mmap`") — and it is the
single largest thing standing between this target and running real programs.
The measurement, at `72b31f73f`: class instantiation, `writeln`, the variant
engine and every float writer are all blocked on it, and **nothing else is**.

The argument, and it is the second time this plan has met it:

> **The ordering in this plan was derived from what wasm makes DIFFERENT. The
> real order is set by what every program NEEDS.**

The data segment gated Phase 4's milestone; the heap gates Phase 5's. Two
incidents make a pattern and a pattern makes a reordering. Everything this plan
put early is early because it is *unusual* on this target — the dispatch loop,
the shadow stack, the value model — and every one of those is now done, while
the ordinary machinery a program cannot start without was scheduled last
because it is boring.

- **Milestone:** `virtual_slice.pas` **runs**, and its 7 values match the
  native build. That slice already exists, already compiles, and already
  validates (Phase 5); it is not run because every path to a virtual call
  begins with a class instantiation. So this milestone is stated as *the
  previous phase's unfinished half becoming true*, which is a milestone nothing
  can satisfy by deleting a message.
  **Met on the wasm side, and NOT met as a phase.** All 7 values match. Virtual
  dispatch, `inherited`, dispatch through a base type, and construction all
  work — **on a heap that starts at address 0.**
- **The heap was not what blocked the heap, and my own diagnostic said it was.**
  Every unlowered builtin printed `needs the heap`. That was assumed from the
  two members of the set that are true (`GetMem`, `FreeMem`) and it was wrong
  for the ones that mattered: `PXXAlloc` itself was blocked on an `Integer()`
  CAST, and the write path on `Trunc`. Both are cheap, neither is the heap,
  and the message asserted a cause in a report that is then read as evidence.
  **A diagnostic that names a CAUSE is asserting a root cause**; it now names
  the BUILTIN. Found by dumping the IR rather than believing the message.
- **`HeapMmap` has no wasm32 arm** — a per-target `{$ifdef}` chain that matches
  nothing, so `Result` is unassigned and returns 0. `PXXAlloc` does not check
  it, deliberately: on a hosted target a failed `mmap` returns a negative errno
  and the next access faults. **Linear memory has nothing to fault on** —
  address 0 is legal, loads return zero, no page protection — so the allocator
  bumps from 0 and hands out 8, 32, 56. Measured, correct, and correct only
  until ~1 KB, after which it overwrites BSS at 1024.
  **This is the shared-file escape this plan predicted for a later phase,
  arriving here.** `compiler/builtin/builtinheap.pas`, one additive arm with
  the shape `PXX_ESP` already has. Filed, not fixed:
  [[bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero]]
  (prio 70). `check_calls.sh` asserts the limitation is **still exactly this
  one** — it fails if the heap starts working, because that means the ticket
  landed and the block is stale.
- **Second milestone — `writeln`. Met on the wasm side; blocked on one shared
  arm, exactly like the first.** `IR_WRITE`/`IR_WRITELN` lower (`3f99f2034`),
  and a `writeln` program compiled to wasm32 prints under node's WASI with
  output byte-identical to the native build — **measured with the shared arm
  applied locally, then reverted.** What is committed is everything except that
  arm: [[bug-a-pxxsyswrite-has-no-wasm32-arm]] (prio 70, filed on master with
  the patch and both measurements).
- **There was no write codegen to write.** The plan said "`IR_WRITE` plus
  `PXXWriteUIntD`", expecting the integer formatter to be the work. It was
  already done: `builtinheap.pas` carries a target-neutral console family —
  `PXXWriteNL`, `PXXWriteDecW`, `PXXWriteCharW`, `PXXWriteBoolW`,
  `PXXWriteStrMW`, `PXXWriteFrozenW`, `PXXWriteCStr` — written when hosted
  riscv32 hit this same wall, carrying the comment *"any backend could adopt
  them"*. This one adopts them unchanged, and a const string costs one call
  rather than the register backends' two, because a literal in `Data[]` already
  **is** a frozen string buffer (measured: `0a 00 00 00 00 00 00 00
  'QWERTYUIOP'` at the offset the call passes). Third time this plan has
  budgeted for work the RTL had already done — see the `PXXAlloc` scope note
  above and the `AddMethodFix` finding in Phase 5.
- **`external 'lib' name 'sym'` IS a wasm import, and no shared file had to
  learn that.** The plan expected host imports to need a mechanism. A wasm
  import's module/field pair is exactly what the Pascal form carries, and both
  halves were already recorded by the parser — `ProcLibrary` and `ProcExtName`
  (`pasparser_proc.inc:1298`), populated since forever and read until now only
  by the ELF writers. **Second escape this plan predicted that dissolved on
  inspection rather than on argument** (the first was Phase 5's `AddMethodFix`).
  Both dissolved the same way: trace the fact to where it is actually stored,
  instead of inferring from the first grep. It also changes Phase 8 — the PAL
  becomes a set of *declarations* in Pascal source rather than a set of backend
  special cases.
- **The bug this phase actually had to fix was in the index space, and it was
  silent.** Imports occupy the LOW function indices, so registering one shifts
  every DEFINED function's index by one — and an import is registered whenever
  the frontend first reaches an external call, which is after most bodies are
  emitted. A module whose indices were baked before that **still validates**:
  every callee has some signature, and enough of them match. It just calls the
  wrong functions. Nothing stores a function index now: calls emit a
  fixed-width placeholder plus a relocation, the table and export table store
  slots, and the bias is applied in one function from the three write-time
  emitters. `WasmCall` no longer *accepts* an index, so the wrong form is
  unspellable rather than avoided. **Measured both ways, because it is silent:**
  with the relocation removed, a module WITH an import is rejected with 127 type
  errors, and a module WITHOUT one is accepted unchanged — *all eight suites
  that existed before this phase are in the second category and none of them
  could ever have caught it.*
- **The `.wat` oracle earned its keep on the same module, on a bug of the same
  shape.** Our text used inline signatures, so a parser numbered types by text
  order while the binary used ours; the two agreed by coincidence until an
  import — which must precede the functions in text — became the parser's type
  0, and every `call_indirect (type N)` then named a different signature in the
  two modules. The `.wat` now declares the whole type table up front, so the
  numberings agree by construction. **An oracle whose only input is a module the
  same generator produced can still find this**, because the two encodings
  disagree about it — which is the cheapest kind of manufactured
  disagreement there is.
- **Scope note, and it did not survive contact.** The plan expected to write a
  bump allocator. **There was nothing to write:** `PXXAlloc(size, align)` is an
  ordinary Pascal routine in the builtin unit and every backend simply calls
  it — the x86-64 path spends its lines saving registers around that call,
  which is the whole of what this target does not have to do. What the backend
  owes is the four steps *after* the allocation (store the VMT pointer, run the
  constructor, return the instance, not the constructor's own result), and
  those are the same on every target. `memory.grow` never came into it.
- **A fresh scratch local per allocation SITE, not one per body.** `z[0] :=
  A.Create; z[1] := B.Create` is three sites in one body, and a constructor
  argument may itself allocate — a shared local is clobbered by the inner
  allocation between the outer store and the outer read. One local per site is
  correct by construction and costs a locals-vector entry.

## Phase 6.5 — frozen strings — **DONE 2026-08-28**

Named by Phase 6's closing measurement rather than by this plan, which is the
point: `IR_STORE_SYM` of a `tyString` was the blocker under the variant
engine's last two bodies, and it is needed for every `string[N]`, `ShortString`
and record string field.

- **Milestone:** `test/wasm/check_frozen.sh` — twelve lines diffed against the
  native build, covering the literal, `Char`, frozen→frozen and empty sources;
  truncation in three shapes; `Length`; indexing; a record field and the
  neighbour an overrun would hit; and `const` and by-value frozen parameters.
  123 of 128 bodies, the five being three bodiless `IInterface` methods and the
  two managed-string refusals below.

**The general statement, which is what made it small:** a frozen string
EVALUATES TO ITS ADDRESS. That is the IR's own convention, not this backend's
invention — the x86-64 arm for a string-valued expression is a bare
`IREmitNode` and a comment saying the address is in rax
(`ir_codegen.inc:6765`). Stating it once in `WasmEmitValueAs` (accepting a
frozen type where an i32 is wanted, and only there) rather than at each
consumer is what let the write path, the store path, `Length`, indexing and
argument passing all arrive together. Three IR shapes evaluate to an address
and report their own type as `Pointer` — `IR_LEA`, `IR_FIELD`, `IR_INDEX` — so
`WasmStrTypeOf` answers what is THERE rather than how it is reached, in one
place, for the same reason.

**The ABI oracle was already the answer to the parameter half, and this lane
was not consulting it.** `abi.inc` opens by naming the exact shape it exists to
delete — a `Syms[...].IsRef or` chain inside an `ir_codegen*.inc` — and this
backend had two of them. They were not merely stylistic: a frozen-string VALUE
parameter is passed as the address of a buffer on every target, and the flag
that says so lives on the parameter's SYMBOL, not on the proc's declaration
record. So `const x: ShortString` came back with *no wasm value type*, and the
callee plus every call site went unreachable — a missing convention reported as
a missing type. Two calls to `ABIParamSlotHoldsValueAddr` / `ABIParamSlotIsPointer`
replaced them, and frozen parameters worked immediately, by-value copy
semantics included (`bug-a-set-and-shortstring-value-params-alias-the-caller`
is the shape that would have failed; `Mut` in the slice is the check).

**What this phase REMOVED from the lowered count, deliberately.** `PXXVarBinOp`
and `PXXVarNot` lowered for about an hour, and they were lowering *wrongly*:
a managed string's slot is pointer-sized, so `m := 'lit'` went down the scalar
path and stored the address of the literal's frozen `[len][chars]` blob AS IF
it were a heap handle. The module validated and ran; every later read was off
by the 8-byte prefix, measured as `s := m` copying
`0c 00 00 00 00 00 00 00 from ma` into a `string[15]` where FPC and the x86-64
build both give `from managed`. Assigning a managed string is
materialise-from-literal, or retain, or move-without-retain, then release the
old handle — a phase. It now refuses by name, and the two variant bodies went
back to unlowered, which is the honest number.

**Two findings worth more than the code:**

- **The `.wat` oracle caught a defect the `.wasm` could not have.** Locals are
  INDICES in the binary and NAMES in the text, so a local allocated per SITE
  rather than per body — `$fzdst` for a second frozen store, `$newobj` for a
  second allocation — costs the binary nothing and makes the text module
  invalid (`redefinition of local`). The `.wasm` validated, ran, and matched
  the native build throughout. Fixed in `WasmAddLocal`, not at the callers: the
  callers are right to want a fresh local per site, and asking each of them to
  invent a distinct name is asking every future one to remember.
- **A silent `Exit` in a value path is a stack underflow reported at the wrong
  line.** `WasmEmitLoadSym` used to Exit without pushing anything when the slot
  had no wasm value type. The module then fails validation at some later
  instruction, naming a line that is fine. It reports now.

**What is refused, by name, and why the message says which:** a frozen string
as a RESULT. That is `abi.inc`'s `RetViaHiddenDest` — the caller allocates the
destination, the callee copies its Result local into it and returns the
pointer — and it is ONE mechanism shared with records, sets, variants and
promotable ints. All five arrive together when the extra i32 parameter is
threaded through `WasmSigForProc`, the call sites and the epilogue. The
refusal names the convention rather than the type, because "no wasm value type"
sends the reader looking for a type mapping that does not exist.

## Phase 7 — exceptions **(the one remaining shared-file escape)**

Pending-flag threading: within a function a longjmp is `$label := N; continue`
(free in the dispatch layout); across functions it is an early return plus a
check after each call, branching to the frame's landing label.

- **Milestone:** `try`/`except`/`finally`, nested, with the native build as
  oracle.
- **~~Risk: not prototyped~~ — retired 2026-08-27. It is now prototyped**, and
  the design holds: [`phase5-exceptions.md`](phase5-exceptions.md),
  `test/wasm/proto/check.sh`. Five compositions (nested finally-in-except, an
  exception across two frames, escape from a loop, catch-and-re-raise, and
  `break`/`Exit` through a finally) produce a trace identical to the native
  build, with `$sp` balanced across the unwind paths. Three things the plan did
  not say, now known: the finally continuation is **one i32 local** that absorbs
  normal/unwind/break/continue/Exit alike; there is **no runtime handler stack**
  at all, in or across frames, because landing pads are statically known; and
  the post-call check **must** dominate every use of the call's result — which
  wasm's validator enforces structurally, so bad codegen fails validation rather
  than returning a wrong answer.
- **Still open** (see that doc's last section): raise-inside-finally, typed
  handlers and the exception object's refcount lifecycle, and anything crossing
  `call_indirect`, which waits on Phase 5.

### Phase 7 — **DONE 2026-08-28**

- **Milestone:** `test/wasm/check_exc.sh` — nine compositions diffed against
  the native build over 25 lines, plus an unhandled raise exiting 217 with a
  line on fd 2, agreeing with the native build on both. `test_exception_finally`
  and `test_exception_typed` from the main corpus are byte-identical too.

**What the trace changed before a line was written.** The prototype's central
finding — "there is no runtime handler stack, landing pads are resolved at
compile time" — was a property of its INPUT, not of the design. Against the
real IR a `try` emits **two** `EXC_LEAVE`s per `EXC_ENTER` (the pad pops the
frame it was entered through), and `EXC_LEAVE n` pops several frames at a point
the lexically following code is still inside all of them. A linear scan derives
the wrong nesting *silently*: the module validates, the exception lands in a
real pad, and the wrong handler runs only for inputs that exercise the nesting.
The correction is in `phase5-exceptions.md`; the design that replaced it keeps
the runtime chain every register backend already has, in the same shared BSS
slot, with one extra word per frame — the `$fp` that pushed it.

**Why that costs nothing, and it is about the LAYOUT rather than about
exceptions.** `$pc` is already a variable feeding a `br_table`, so branching to
a computed basic block is the same instruction as branching to a constant one.
A dynamic landing pad is free here where on a register target it would be an
indirect jump. Second time this phase that the dispatch layout has paid for
something it was not chosen for. General form: **any control transfer whose
target is data rather than syntax is free in this layout.**

**The mechanism, in full, because it is small:** a raise sets a pending flag
and the shared status words, then asks one question — `[$exc_top + 8] = $fp`?
Yes, and it is ours: `$pc := [$exc_top + 4]; br $dispatch`. No, and it belongs
to a caller: restore `$sp` and `return`, and the caller's post-call check asks
the same question of its own frame. `return` rather than a branch to the
epilogue, deliberately: branching there would force every body containing a
call to grow a `br_table` it does not otherwise need.

**The gate that keeps this free for everyone else.** Post-call checks are
emitted only when `ExceptionUsed` — the frontend's own flag. A program with no
`raise` anywhere emits a module with no pending flag and no checks, so every
module that existed before this phase is unchanged. That property is invisible
to a differential (the checks would be *correct*, merely universal), so
`check_exc.sh` asserts it directly, and asserts it BOTH ways so the negative
cannot pass by naming the wrong symbol.

**The rule the prototype found by getting it wrong, now enforced structurally:**
a call's result is spilled to a local before the check. The check ends in a
`br` on the unwind path, and a branch cannot carry a half-built expression.

**Refused and filed, not hidden:** the proc CLEANUP frame, which releases
managed locals when an exception unwinds THROUGH a frame rather than being
caught in it. wasm32 sits outside `TargetHasProcCleanupFrame` exactly as xtensa
deliberately does. An unwind leak prints nothing — invisible to the very
differential this phase is gated on, because both sides produce identical
output and only the heap differs — which is why it is
`bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa` and not a comment.

**The shared-file escape did NOT dissolve** — the third one predicted, and the
first to survive inspection. `exception_emit.inc`'s wasm32 arm had to stop
erroring. It is four lines in an arm that is dead on every other target, and
the in-file precedent was sitting four lines above it: xtensa already sets its
three addresses and emits no runtime. One deliberate difference — xtensa
follows them with `EmitExit`, because its stub is REACHABLE and the trap is the
difference between a clean exit and running whatever follows; wasm's is not
reachable by construction, since there is no way to express a jump to a code
offset, so the useful value is a POISON (-1) rather than a trap. Taken under a
branch-only grant that is explicitly **not** merge permission: all three of the
branch's shared-file arms present as one reviewable set at merge time.

## Phase 8a — managed strings, slice 1: publish — **DONE 2026-08-28**

The plan said the PAL was next; the measurement said otherwise, so the
measurement won. On the 236-body corpus (`test/test_variant.pas`) the refusal
histogram read **182 of 236 lowered, 51 refusals, 32 of them the single line
"assignment to managed string"** — one cause, four fifths of the mass. That is
a phase, not a list, so it was taken ahead of the PAL.

**What a managed store is.** Not one instruction. The slot is pointer-sized, so
the wrong lowering VALIDATES and RUNS: `s := 'lit'` stores the address of the
literal's frozen `[len][chars]` blob where a heap handle belongs, and every
later read is off by eight bytes. The right one is three steps in a fixed
order — materialise a handle the slot will own, publish it, release what the
slot held — and the order is the aliasing rule, not a style choice: `s := s`
and `s := t` where `t` aliases `s` both pass through it. Source shapes:
literal, `Char` (via an 8-byte frame scratch above the handler frames),
frozen string, another handle, and the already-owned results — a concat or a
call, discriminated by `IRNodeOwnsManagedStr`, the shared predicate every
register backend uses, already forwarded ahead of this file in `compiler.pas`.

**The half that was not in the plan: zero-init.** A managed local's slot is
shadow-stack memory, and the publish sequence READS it to find the handle it
must release. `Make`'s first `Make := 'one'` therefore handed the caller's
leftover `writeln` bytes to `PXXStrDecRef` and trapped. Every register backend
zeroes these in its prologue and each of the four notes at
`ir_codegen.inc:10037` is a bug where a slot was released before it was written;
those passes emit through `EmitZeroFrameSlot`, which has no wasm arm (filed:
`bug-a-emitzeroframeslot-has-no-wasm32-arm`, with the fork about which
mechanism owns the guarantee). So this target zeroes in its own prologue, in
`WasmEmitManagedLocals` — **one procedure with a flag, entry and exit sharing
one predicate**, because zeroing a slot the exit does not release leaks and
releasing one the entry does not zero is the trap above.

**A refusal that held only by coincidence, found on the way.** `WasmEmitBinop`
refused string operands from INSIDE the arm that runs when the width oracle
fails. `s + 'x'` is a handle and a `Char` — pointer-sized and ordinal — so the
oracle agreed on i32 and the guard was never reached: `t + '/' + 'z'` lowered
to `i32.load; i32.const 47; i32.add; i32.const 122; i32.add`, and
`writeln(t + 'x')` in a body with no managed store at all lowered to
`handle + 120` passed to `PXXWriteStrMW` — measured on the branch BEFORE this
phase, so it is a pre-existing hole this phase exposed rather than opened. The
managed-store refusal had been masking it in the common shape. The guard is now
above the oracle. **A refusal that depends on a different check happening to
fail is not a refusal.**

**IR_LEA of a scalar managed string** now yields the HANDLE. It is
position-dependent in the register backends (read → handle, write → the slot's
address) and they tell the two apart with the global `InLValueWrite`, which
only backends assign — so on this target it is permanently False and cannot be
believed. Instead: every write-position consumer refuses somewhere else
(`SetLength` is builtin -102, `s[i] := c` is `WasmEmitIndex`, concat is the
binop guard above), so every IR_LEA that arrives is a read. That is an argument
from what currently refuses — the same shape as the coincidence one paragraph
up — so `check_managed.sh` asserts all three refusals still fire, with the
slice's own zero-refusal count as the positive twin that stops the negative
passing vacuously.

**Result:** 195 of 236 on the same corpus, 38 real refusals. The new mass is
concat/compare (20 of 38: 16 `+`, 3 `=`, 1 `<>`) — slice 2 — then indexing
(8) and `SetLength` (3) — slice 3.

**Scope, stated because the green tick does not say it.** The heap arena still
starts at address 0 (`bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero`,
open, prio 70). The slice passes because its live set is a handful of short
strings the free list recycles inside the first kilobyte. Measured today: past
about 128 KB of live allocation the module traps, because it never calls
`memory.grow`. `check_managed.sh` asserts the heap is STILL broken, so the day
that ticket lands this check fails and the scope note has to be rewritten
rather than quietly outliving its cause.

The unwind path still leaks managed locals — it returns without passing the
epilogue — which is the wasm half of
`bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa`, unchanged.

## Phase 8b — managed strings, slice 2: concat and compare — **DONE 2026-08-28**

The histogram picked this too: 20 of the 38 refusals left after slice 1 were
`` `+` ``, `=` and `<>` on strings. Neither operation is an instruction on any
target, so the whole slice is: split each operand into (length, characters),
push four arguments in the callee's order, call, spill, release any operand
that owned its reference, yield.

**One predicate now answers "is this a string operation"**
(`WasmBinopIsString`), and two consumers ask it: `WasmEmitBinop` refuses or
dispatches on it, and `WasmBinopWidth` declines to unify a width on it so
`WasmNodeResultType` falls through to the IR's own record and answers
`tyAnsiString` rather than the ARITHMETIC width of two handles. That deletes
the special case slice 1 had to add in `WasmStrTypeOf`, which is the tell that
the predicate is in the right place.

**`WasmStrParts` is the (length, characters) rule, once.** A handle carries its
length below itself and must not be dereferenced when nil; a frozen buffer
carries it inline at +0 with the characters at +8; a `Char` carries nothing and
has to be spilled to frame scratch before anything can point at it. Same three
rules as `EmitA64StringParts`, which is where they are written for the register
backends. `WasmEmitLength` was folded onto it — the two were one phase old and
had already diverged in one detail (the FIELD/INDEX deref existed in Length's
managed arm and nowhere else), which is precisely how this drifts.

**Ordered comparison landed with the rest on purpose.** It reached NO cross
backend for a long time: only `=`/`<>` were special-cased, `a < b` fell through
to the integer compare, and `'zzz' < 'aaa'` answered by allocation order —
silently and identically wrongly on four targets. This backend refuses rather
than guesses so it could not have shipped that bug; it could have shipped the
refusal forever, which is the failure mode worth naming.

**The leak assertion took three attempts and found a bug in the oracle.** An
operand that owned its reference must be released after the RTL call, and a
leak changes no output at all, so it needs a heap observable. Attempt one
compared the arena advance against the native build's: wrong, because
`PXXAlloc(64)` is served from a free list once the program has freed anything,
so the two figures were allocator bookkeeping (72 native, 112 wasm, neither
leaking). Attempt two probed with a size the loop never frees, so every call
bumps — and then the two builds disagreed by 40 bytes per iteration.

**They disagreed because x86-64 is the one that leaks.** It releases an owned
managed-string operand after a concat (`ir_codegen.inc:6105/6110`) and not
after a comparison, so `if F(x) = 'lit'` leaks F's result every evaluation:
401032 bytes over 10000 iterations, against 1032 on wasm32 and 0 under FPC. The
four cross backends all carry the release at all THREE sites; x86-64 carries it
at one. That is the exact mirror of
`bug-a-a-string-function-result-in-a-concat-leaks-on-every-cross-target`, which
was the same predicate missing from the four cross backends while x86-64 had
it. Filed as
`bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64` [A, p70].

So attempt three asserts the PROPERTY on wasm alone — the advance must not
scale with the iteration count, 1000 and 9000 iterations giving the same
figure — and separately asserts that native still has the bug, so the note
expires when the ticket lands. **A diff against an oracle is only as good as
the oracle**, and the only reason this surfaced is that the figures were
compared at two iteration counts rather than once.

**The Char scratch had to move to the shadow stack, and the frame version was
wrong in a way only nesting shows.** A `Char` operand is a value, so it must be
spilled to memory before an RTL routine can point at it. The first version
reserved one 8-byte area per BODY, sized in the pre-pass — and string operands
NEST: `a + (b + s)` put the inner Char at the same address as the outer and
printed `BBS` for `ABS`. Reserving storage per body for a thing whose lifetime
is per EXPRESSION is the whole mistake, and a shadow-stack push nests by
construction, which is why every register backend spills its Char onto the
machine stack. The frame reservation, its pre-pass scan and its frame-growth
arithmetic all went away with it.

**And the locals had to be pooled by depth**, because a fresh local per site —
which is what makes nesting safe — hit the encoder's 288 params+locals per body
on a slice with two dozen string operators. Depth is the real bound: an
operand's parts are live from the split until the RTL call, and anything nested
inside has already finished, so siblings share slots and only levels need their
own. Sixteen levels, eight slots each, allocated lazily; deeper is refused by
name.

**Also landed: `IR_ATOMIC`.** A plain load / modify / store, because a wasm MVP
module has exactly one thread of execution, so the sequence is indivisible by
construction rather than by a prefix. The argument is semantic and it is
riscv32's shape (masking interrupts IS the atomic on a single-core part, and it
refuses on a multi-core one) with a stronger premise and no capability table to
ask — whether a module is threaded is a module-level decision this compiler does
not make yet. The precondition that follows is recorded in
`devdocs/dev/threading-model.md` §8 **on master**, not only at the lowering
site: whoever adds shared memory or the threads proposal to this target must
replace `WasmEmitAtomic` in the same change, because the window between the two
is a program that compiles, runs, and is wrong only sometimes.

**Result:** 216 of 236, up from 195 — 211 from the string operators and five
more from `IR_ATOMIC`, which had been five of the `value IR op 63` refusals.
What is left is 17 real refusals and the mass is one cause again — **indexing a
managed string, 12** — then `SetLength` at 3 and two assorted IR ops. Slice 3
is indexing plus `SetLength`, which are the
same mechanism from two directions: both need the SLOT's address so a
copy-on-write (`PXXStrUnique`) or a resize (`PXXStrSetLen`) can publish a new
handle into it. That is also the pair `check_managed.sh` asserts still refuses,
so slice 3 will make that check fail by design — the second time this phase's
own expiry has fired.

**One check corrected itself this slice.** `check_managed.sh` listed THREE
refusals as the support for `IR_LEA`'s read-position answer, and concatenation
was in the list because it refused, not because it was a write position — an
operand of `a + b` is read, and no answer ever depended on it. Slice 2 made
that check fail, which is how the mistake surfaced. **A list assembled from
"what currently refuses" rather than from "what this argument needs" contains
everything that happens to be missing**, and only the failure distinguishes the
two.

## Phase 8c — managed strings, slice 3: indexing and SetLength — **DONE 2026-08-28**

The histogram picked this a third time: 15 of the 17 refusals left after slice
2 were `indexing a managed string` (12) and `builtin SetLength` (3). They are
one question asked from two ends — both need the **slot's address**, so that
`PXXStrUnique` (copy-on-write) or `PXXStrSetLen` (resize) can publish a NEW
handle into it — which is why they landed together and why neither could land
before a position model existed.

**The `IR_LEA` argument was replaced, not extended.** Slices 1 and 2 answered
HANDLE for every `IR_LEA` of a scalar managed string, and the justification was
never that reads are the only position: it was that every write-position
consumer refused *somewhere else*, so no write could reach that line. That is
an argument from what currently refuses, so it was written down rather than
trusted — and slice 3 is what invalidated it, because `s[i] := c` and
`SetLength(s, n)` are precisely the two shapes it named. With both lowering,
there is nothing left to support; trimming the list would have left an empty
assertion under a paragraph claiming a property the build no longer has.

**The position model is the shared global `InLValueWrite`, not a private
flag.** `defs.inc` states the IR contract for `IR_LEA`, `IR_INDEX` and
`IR_DYNUNIQUE` in terms of that global (`defs.inc:747`), so a second flag would
have been a second, undocumented contract. It is safe as a global because no
backend ever leaves it set: every site saves and restores, and it is False
between statements. Set at the three destination walks (`WasmEmitStoreMem`,
`WasmEmitManagedStore`, `WasmEmitFrozenStore`) and at `IR_SETLEN_STR`'s slot
node; **reset** around `WasmEmitIndex`'s index sub-expression, because the index
is a READ even when the whole `IR_INDEX` is a write target.

**Both non-scalar shapes were handled from the start.** A managed string that
is itself a record field or an array element is a slot address in *both*
positions, so the read case needs its own load — riscv32 and arm32 each shipped
the scalar-only version and had to fix it a second time
(`bug-a-riscv32-setlength-on-string-array-element-loses-length`). Writing the
second shape in the same change costs three lines here and cost them a ticket
each.

**Every mechanism was falsified before it was believed.** Four deliberate
breaks, each run against the slice:

| break | what happened |
| --- | --- |
| write case skips `PXXStrUnique` | `Xhared\|Xhared` — **only** the two aliasing lines caught it |
| `IR_LEA` answers handle in write position | the slice **traps** |
| no reset around the index expression | `a?c!` → `abcd`, one silent line |
| `PXXStrSetLen` handed the handle | the program produces **no output at all** |

**And one assertion was vacuous on first write — again.** The check meant to
catch that last row grepped for an `i32.load` before the `PXXStrSetLen` call. A
global's slot address is an `i32.const` and a local's is `fp+N`, so no load
appears in either shape and the grep asserted nothing — while a `var s: string`
parameter's slot address legitimately *is* a load, so the first one to reach
the grep would have failed correct code. It was quantified over the wrong
thing, in both directions at once. **Passing on first write is not evidence
that an assertion is about what you think it is** — the second time this phase
has learned that, after `check_strop`'s module-wide negative control.

**The assertion that survived is the one a diff cannot make.** Collapsing the
model to "always write" — cloning on reads too — gives the *right characters*
and merely leaks: the slice diffs byte-identical (measured). So
`check_index.sh` asserts the two positions emit **different code**: the same
source one line apart, `c := s[1]` calling `PXXStrUnique` zero times and
`s[1] := 'z'` calling it once. `check_managed.sh` keeps the negative half for
its own bodies, scoped to them rather than module-wide.

**The leak probe was taken at two counts by habit now, and both builds are
clean** — 1000 and 9000 iterations of COW-plus-SetLength advance the arena by
the same 1032 bytes on wasm32 *and* on x86-64. That agreement is evidence only
because both slopes are zero; slice 2's lesson is that agreement with the
reference is not the same as correctness, and the check says so where the
figure is printed.

**Result:** 231 of 233, up from 216 of 236. What remains is two real
refusals — `IR_VAR_STORE` (a variant store) and builtin `-205`
(`FloatToStr`).

**The denominator moved because the report was counting non-defects.** Three
`IInterface` methods are DECLARED without implementations; the RTTI blob names
them, so a function index has to exist, and each gets `unreachable` because
calling one must trap. That is the correct code, not a placeholder for missing
code — and they were being counted and announced as holes in op coverage on
every program that links the interface RTTI. The per-body *reason* already said
so; the headline did not, which is the half that gets read. So the report is
now two lines: gaps, which claim incompleteness, and declaration-only stubs,
which do not. Both stay listed — a body that traps at run time must be visible
at compile time, and the day one of these is a real missing body it is on the
page.

That was not cosmetic. **The completion criterion for this backend is that the
count reads N of N**, and three permanent non-defects made it unreachable by
construction: a signal that can never go clean is a signal nobody reads. With
the split, `test_exception_typed.pas` and `test_exception_finally.pas` already
report *op coverage is complete for this program*, which is true and was true
before the change — nothing said so.

**The other check corrected itself for the opposite reason.** `check_strop.sh`
asserts the three RTL calls appear in the slice and in no program without
string operators — and the negative half passed while it was written only
because the RTL's own `PXXVarBinOp` (which calls `PXXStrConcat`) was itself
refused and emitted as `unreachable`. The very change under test made the
symbol appear module-wide. The check is now scoped to `$main$0`, the program's
own body. Same lesson as the `abi.inc` grep calibrated against an empty result:
**a negative control has to be measured on the tree the check will run on, not
on the one it was written against.**

## Phase 8 — the PAL

`lib/rtl/platform/wasi/platform_backend.pas`, sized like `esp/` (1,035 lines).
The PAL surface is **87 entry points**, identical in the posix and esp backends
(measured, not estimated) — so a third backend is a third implementation of one
fixed contract. ESP refuses 37 of them unconditionally; WASI's refusal set is
different in shape rather than in size: ESP has sockets and no files, WASI has
files and no sockets. **Heap growth is no longer here** — it was one line in
this section and it turned out to gate everything, so it is Phase 6 now.

- **Milestone:** a program that opens, writes, reads back and closes a file
  under `wasmtime --dir=.`, and prints to stdout.

### Phase 8d — the PAL SEAM, everything behind it refusing — **DONE 2026-08-28**

Landed first and on its own, because of what it unblocks rather than what it
implements. **Before this file existed, `uses SysUtils` did not compile for
wasm32 at all** — posix is the compiled-in default PAL, it reaches the kernel
through a per-architecture table of Linux syscall NUMBERS, and wasm32 fell into
it and died at PARSE time with `undefined variable (SYS_openat)`. That is not a
gap in the backend; it is a whole third of the RTL unreachable for a reason
that has nothing to do with codegen. With the seam in place a SysUtils program
compiles (642 of 669 bodies) and its output is byte-identical to the native
build's.

**Why a third backend and not an arm of the posix one.** wasm has no syscall
instruction and no number space: a host call is an IMPORT, named by module and
field, resolved at instantiation. There is nothing to add a `{$ifdef
CPU_WASM32}` block to — the mechanism differs, not the constants.

**No shared-file edit, and the reason is documented rather than lucky.**
Selection is `-Fu` on the unit search path, and `AddDefaultPasUnitDirs` appends
the posix default *after* the user's `-Fu` dirs specifically so an explicit
override wins. Making wasm32 pick the wasi directory by DEFAULT would be a
`compiler.pas` change and a fourth shared-file arm on this branch; the shape
for it already exists in that same function (ESP targets are excluded from the
default), so it is available if the explicit form ever proves unworkable. It
has not been taken.

**Everything refuses, and that is the deliberate failure mode, not a
placeholder.** All 87 entries return `PAL_ERR_UNSUPPORTED`, so a program that
opens a file meets runtime error 38 (ENOSYS) — asserted, because "unimplemented"
must be distinguishable from "trapped" and from "wrong answer". It is the model
Track S established for ESP.

**The check nearly shipped a `|| true`, and what it was hiding was worse than
the check.** `wat_oracle.sh` takes four positional arguments and passes no
compiler flags, so calling it for a slice that needs `-Fulib/rtl/platform/wasi`
compiled the slice WITHOUT the flag, failed, and could only be kept green by
swallowing the exit status. Making the flags pass through instead turned up a
real bug: **the WAT emitter's function identifiers were not injective.** It
rendered `(func $Name)` and `call $Name` from the Pascal name, and Pascal names
are not unique — `uses SysUtils` declares `DateTimeToStr` and
`AdjustLineBreaks` twice each. wat2wasm rejects the redefinition, which is the
good failure mode, but depending on the reader's tool to reject a module we
should not have emitted is not a property. Every slice for nine phases happened
to have unique names. Fixed by making the slot part of the identifier
unconditionally: per-name suffixing cannot be done at the point the text is
written, because a call is emitted while its callee may not exist yet.

**Remaining refusals with SysUtils in play (27), as the next histogram:** nine
`value IR op N`, seven `the slot holds a heap handle` (dynamic arrays), three
records returned through a caller-owned hidden destination (`RetViaHiddenDest`
— a new class, and the reason `PalIn6Any` and `DateTimeToTimeStamp` do not
lower), two `SetLength` on a dynamic array, and assorted singles.

### Phase 8e — the WASI file core — **DONE 2026-08-28. MILESTONE MET.**

`open / read / write / seek / close / sync / flush`, `unlink / mkdir / rmdir`,
`rename`, and both clocks, over WASI preview1 imports. **A program writes a
file, closes it, reopens it, reads it back, appends, truncates, seeks from both
ends, renames, erases and removes a directory — and its output is byte-identical
to the native build's, with the sandbox left empty.** That is the Phase 8
milestone, reached against node's own WASI rather than against `wasmtime`,
which is not installed on this box; both are preview1 hosts and the point of the
milestone is the host being independent, not which one it is.

**The oracle is deliberately not ours.** `wasmhost.js` is a shim this project
wrote, and a shim written alongside the backend it tests agrees with that
backend by construction — including where both are wrong. It also has no
filesystem, so there is nothing for it to disagree about. `node:wasi` is an
independent preview1 implementation with real preopens, which is also what
makes the capability model testable at all.

**What has no posix counterpart: path resolution.** There is no `open(path)`. A
program may only reach directories the host PREOPENED, arriving as descriptors
3, 4, ... each with a name, and every path call is `(dirfd, relative)`. So the
backend scans the grants once and resolves each path against them, longest
match wins. A path under no grant is **ENOENT, not EPERM** — in the namespace
this program was given it genuinely does not exist, and EPERM would suggest a
permission that could be raised.

**Two things that are invisible to a happy path and were falsified rather than
assumed:**

| break | what the slice reported |
| --- | --- |
| WASI errno passed through unmapped | every line diverges from the first |
| read rights not requested at open | `read=-1`, then `Runtime error 1` — the fd OPENS and fails on first use |
| `SEEK_CUR`/`SEEK_END` transposed | `seek-end-2=4` (want 8), `tell=10` (want 9) — every read still returns SOMETHING |

The last two produce *different* failures, which is the point of running both:
identical signatures would have meant one assertion wearing two names.

**Errno numbering is a real hazard, not a formality.** WASI's errno list is
alphabetical and Linux's is not, so WASI 2 is EACCES where Linux 2 is ENOENT.
Both are non-zero, so a build that passed them through turns every missing file
into a permission error and anything asking only "did it fail" agrees. Only the
codes a file API can produce are mapped; the rest become `-5` (EIO) — "the host
refused and we have no better name for it" — rather than a plausible wrong code.

**Modules now export `_start` as well as `main`.** `main` is our own convention
and what the JS harness calls; every real WASI host — wasmtime, wasmer, node —
looks for `_start` and refuses to run a module without it. Two exports of one
function is the difference between a module a harness can drive and a module a
host can run.

**And a mirror of slice 2's bug, found by this slice.** `WasmBinopIsString`
asked only about the OPERANDS, so `frozenString + 8` — which is exactly how
`PChar('literal')` lowers — was refused as "concatenation producing Pointer".
True about one operand, false about the operation, and it made every program
that passes a string literal to a `PChar` parameter fail, which is most of the
PAL. The fix splits the question by operator, because the two cases key on
different things: a **comparison** keys on the operands (`a = b` is Boolean
whatever a and b are), a **`+`** keys on the result (an operand being a string
is not enough, because a frozen string's value is its address). Slice 2's bug
was a string operation not recognised because an unrelated check succeeded
first; this is a non-string operation recognised because a related check is
true of one operand. Both come from asking about the pieces instead of about
the operation.

**Still refusing, and honestly:** everything WASI has no answer for — no fork,
exec, wait, kill or pipes; no `socket()`, `connect()` or `bind()` (preview1 has
`sock_send`/`sock_recv` for descriptors a host hands in, and no way to create
one); no users, so no `getuid`/`chmod`/`chown`; no `mmap`; no `dlopen`. Plus
the ones that are simply not written yet — `stat` and its family, `readdir`,
`poll`. `PAL_ERR_UNSUPPORTED`, as with ESP.

## Phase 9 — the anchor: `pascal26` under wasmtime

The compiler itself: single-threaded, file I/O only, no sockets, no fork. It is
the one large program that fits this platform exactly.

### Measured first, 2026-08-28 — Phase 9 is ONE feature, not a list

`compiler.pas` compiled for wasm32 (`-Fulib/rtl/platform/wasi`), on a **probe
build** whose only change was stubbing `EmitZeroFrameSlot`'s two wasm-reaching
arms so the run would not stop at the first hard error. That probe is a
measuring instrument and nothing else: the module it emits has no zero-init and
must never be run for a correctness claim.

**3647 bodies, 2056 lowered, 1591 refused** — and the compile *completed* and
wrote a `.wasm`. 881 distinct refusal lines. The histogram:

| lines | refusal | share |
| --- | --- | --- |
| 681 | dynamic array — layout not implemented | |
| 23 | open-array parameter (the slot holds a dynamic-array handle) | |
| 15 | `SetLength` (builtin -102) on one | |
| 10 | `Length` of a Pointer | |
| **729** | **the dynamic-array family** | **83%** |
| 68 | set membership, `in` (`-SPECIAL_IN`) | 8% |
| 59 | `IR_DEFAULT_MEM` (op 52) — zero a managed aggregate | 7% |
| 5 | record returned through a hidden destination (`RetViaHiddenDest`) | |
| 5 | `LoadFile` (builtin -100) | |
| ~10 | the tail: `FloatToStr`, `PXXMemMove` of a non-string, `IR_SETLEN_DYN`/`IR_DYNUNIQUE` as statements | |

**The list of remaining gaps was the wrong shape and this is why it is worth
measuring rather than planning.** Carried into this phase as five roughly
comparable items — dynamic arrays, record returns, `FloatToStr`, `IR_VAR_STORE`,
SetLength — it is in fact one feature at 83%, a second at 8%, and a tail. Record
returns, which read as a peer of dynamic arrays on the gap list, are **five
lines**. Ordering the work off that list would have spent the phase on items
worth under a percent each.

`in` is the surprise and the cheap one: 68 bodies, every register backend
already handles it (`j = SPECIAL_IN`), and it was reporting as
`builtin unrecognised (-999)` — the one label that tells a reader nothing about
how big a gap is. Now named, confirmed by repro (`if i in [1,2,3]`) rather than
inferred from the constant.

`IR_DEFAULT_MEM` at 59 is the same guarantee as the `EmitZeroFrameSlot` finding
below, one level up in the IR: zeroing a managed aggregate. Whoever takes either
should look at both.

### Phase 9a — dynamic arrays, the flat case — **DONE 2026-08-28**

The 83%. `SetLength`, index read and write, `Length`, aliasing, shrink and
grow, an `array of string`, and both releases — byte-identical to the native
build, arena slope zero on two independent probes.

**The IR dump changed the plan before a line was written.** The flat case emits
no `IR_SETLEN_DYN`, no `IR_DYNUNIQUE` and no `IR_SLOTADDR` — those are for
nested and field-rooted targets. It is `IR_LEA`, builtin `-102`, `IR_INDEX` and
builtin `-44`, which is four things and not the op-set the histogram's names
suggested. `PXXDBG=a.ir:<proc>` cost one command; reading the backends and
guessing would have cost an afternoon and produced two ops nothing emits.
(Note it is gated on `CurProc >= 0`, so a program's MAIN body can never match,
`a.ir:*` included — put the code in a named routine.)

**No shared-file arm was needed, and that was checked rather than assumed.**
`GetOrAllocSymRTTI` and `GetOrAllocNodeDynDesc` are already forwarded in
`compiler.pas` on master; `EmitRTTI` fills the descriptors and is not
target-gated; `WasmFillData` already applies `DataPtrFix`. All three were
verified before the arm was written, because the alternative is discovering at
run time that a descriptor is twenty zero bytes.

**The slot-versus-handle rule, again, one type over.** `IR_LEA` on a dynamic
array yields the DATA pointer in read and write position alike — no
copy-on-write, because a dynamic array is a reference type at every depth and
`b := a` is meant to alias. So `SetLength` cannot go through `IR_LEA`: it needs
the slot, and `PXXDynSetLen` treats a nil `arrSlot` as *nothing to do*, so a
build handed the handle of a fresh array reports success and allocates nothing.
riscv32 shipped exactly that.

**The leak probe earned its place again.** The first working version passed the
diff completely and leaked 10512 bytes per 1000 iterations where native was flat
at 1032; at 9000 it exhausted linear memory and trapped. `b := a` was falling
into the SCALAR store path, which copies the handle — correct aliasing, absent
refcount. Nothing in the output ever looked wrong.

**Five breaks, five signatures — and the fourth of them exposed a hole in the
suite rather than confirming it.**

| break | signature |
| --- | --- |
| retain removed from the store | the diff: `a0=7777`, a use-after-free |
| scope-exit release removed | probe B leaks 26432 bytes/1000 |
| the store's release removed | probe A leaks 10464 bytes/1000 |
| `SetLength` handed the handle | the diff: every length reads zero |
| the `Length` nil guard defeated | trap, `memory access out of bounds` |

The two leak probes are deliberately separate programs — one with no local
arrays, one with no assignments between arrays — because a single probe
exercising both would go red for either, which is one assertion wearing two
names. Breaks 2 and 3 hitting *different* probes is what makes them two.

**The retain break PASSED the first version of the check, and that is the
finding.** A missing retain makes refcounts too LOW, which is a premature free,
not a leak — the opposite direction from everything an arena slope measures.
Worse, it is invisible even in the output until the freed block is REUSED: the
stale bytes survive and the wrong build prints the right answer. The assertion
that catches it allocates a same-sized array between the free and the read.
**A leak probe is a one-directional instrument** — it sees refcounts that are
too high and is blind by construction to refcounts that are too low, which is
the direction that corrupts rather than wastes. Every refcount check needs both
halves, and this suite had only one for three phases.

**A latent encoder bug fell out of it.** `WasmIf(bt)` wrote the block type
correctly into the BINARY and emitted `if (result)` — with no type — into the
WAT. Not valid WAT, so a typed `if` would have produced a module whose `.wasm`
and `.wat` disagreed, which `wat_oracle.sh` would have caught as a mystery. No
caller had ever passed anything but `WT_VOID`, so it had never fired. `WasmLoop`
had the identical defect one procedure below and was fixed at the same time
rather than when someone reached it.

### The coverage argument had a date on it, and dynamic arrays had already crossed

The audit above concluded that the string slices cover the premature-free
direction because a string's refcount is READ by the code under test — COW asks
"am I sole owner?" — while a dynamic array's is read only on release. True, and
the wrong kind of true: **that is a property of the current semantics, not of
the type.**

`IR_DYNUNIQUE` still exists in four backends and its own comment opens *"The
name is now historical"*. Dynamic arrays USED TO have copy-on-write; the clone
was deleted when `decide-dynamic-array-value-vs-reference-semantics` settled on
FPC reference semantics. So dyn arrays were once the first kind and became the
second kind by a decision made elsewhere — and the two directions are not
symmetric:

* second → first (COW added): the reuse-forcing control becomes redundant.
* **first → second (COW removed): the second observable route disappears, the
  diff stops witnessing a too-low refcount, and every existing test keeps
  passing.**

Dynamic arrays took the dangerous one. A suite written while COW existed became
an uncovered suite, and nothing in any output changed. **A coverage argument
that rests on "the code under test reads this value" depends on a design
decision, and design decisions are not versioned against the tests that assume
them.**

So the rule gains a clause rather than being replaced: *ask which kind you have
before trusting a green suite* still holds, and **where the reuse-forcing
control is cheap, design it in even for a first-kind type** — it costs one
allocation and it is the only witness that survives a category change in either
direction.

Applied rather than noted: `check_managed.sh` now carries that control as its
own assertion, aliasing a string, dropping one reference, forcing the allocator
to hand the block out again, and reading through the surviving name. It does not
go through COW at all. Falsified with the retain removed: it prints sixteen Z's
where the correct build prints the string, and it fires independently of the
diff lines that were already catching it.

### Re-measured after the slice — and the histogram was a ranking of what is REACHED

`compiler.pas` for wasm32, same probe build, after Phase 9a:

| | before | after |
| --- | --- | --- |
| bodies lowered | 2056 of 3647 (56%) | **3222 of 3650 (88%)** |
| bodies refused | 1591 | **428** |
| refusal lines | 881 | 431 |

The dynamic-array family is **gone** from the histogram — not reduced, absent.
But the total did not fall by its 83% share, and what replaced it is the
finding:

| lines | refusal | was |
| --- | --- | --- |
| 267 | set membership, `in` | 68 |
| 74 | `IR_DEFAULT_MEM` (op 52) | 59 |
| 30 | open-array parameter | 23 |
| 15 | builtin -50 | 4 |

**`in` went UP, from 68 to 267, and nothing about `in` changed.** A body reports
its FIRST refusal and stops, so the histogram ranks what each body *reached*,
not what it is missing. 1163 bodies stopped at a dynamic array before they could
discover they also needed `in`. Removing the leader does not subtract its share;
it PROMOTES everything the leader was masking.

So the earlier reading — "one feature at 83%, then a tail" — was right about
the leader and wrong about the tail, and it was wrong in the direction that
matters for planning: the tail was never small, it was hidden. The honest form
of the claim is that the dynamic-array family was 83% of what programs hit
FIRST. `in` is now 62% of the remainder on exactly the same reasoning, and the
same caution applies to it.

This is the diff-versus-summary lesson one level in. A histogram is a
measurement, and it still misled, because the quantity it counts is not the
quantity it appears to count. **Measuring the right thing is a separate act
from measuring.**

### The blocker Phase 9 actually starts at, and a correction it forced

The unprobed compile stops at `compiler error: EmitZeroFrameSlot: unhandled
target` — `bug-a-emitzeroframeslot-has-no-wasm32-arm`, already filed. Measuring
it corrected that ticket.

`EmitZeroFrameSlot` has **two** per-target chains, one per size class. The wide
one (`> TARGET_PTR_SIZE`) ends in `Error` and fails loud, which is what the
ticket described and what its priority rested on. The narrow one
(`<= TARGET_PTR_SIZE`, i.e. **every managed scalar**) ends in an **unguarded
`else` that is the x86-64 arm** — so wasm32 has been silently emitting
`mov qword [rbp+off], 0` for every managed local since the managed-string phase.

Found by probe, not by reading, and the reason a read missed it generalises: six
named target arms and an unnamed seventh reads as "the default" when it *is*
x86-64. **A dispatch chain whose last arm is a real target rather than an error
is a fall-open chain wearing the shape of an exhaustive one.**

Severity measured rather than assumed: a second probe build emitting nothing
there produces **byte-identical** `.wasm` for `managed_slice`, `index_slice` and
`wasi_slice`. `Code[]` is not read on this target, so nothing wrong has ever come
out of it — latent, not active. It stops being latent the moment anything here
reads `Code[]` or its length.

### A reason that outlived its phase, twice in one file

The dynamic-array refusal said **"needs the heap, Phase 6"**. Phase 6 shipped the
heap. The refusal stayed correct and its stated cause stopped being true — and
what is actually missing is the dynamic-array *layout* (descriptor, refcount,
length, element arithmetic, `SetLength`, copy-on-write), none of which the heap
provides. The same phrase was still in the calls note, asserting that every
builtin "needs the heap, Phase 6" when `SetLength` on a string lowers here today.

This file already carried a note retiring that exact phrase for the builtin
report, written when it was found to be an assumed cause rather than a measured
one. It was retired in one place and left standing in two others. **Correcting a
wrong reason where you found it does not correct it where it was copied to** —
grep the phrase, not the site.

### Phase 9b — set membership `in` — **DONE 2026-08-28**

62% of what was left. `WasmEmitSetIn` lowers `x in [items]` as a single
expression: the test value into a scratch local, an i32 accumulator, then per
item either an equality or a `ge_s`/`le_s` pair `and`ed together, `or`ed into
the accumulator. Width follows the test value — i64 compares for a 64-bit one.

**Branchless, and not by cleverness.** Every register backend jumps around each
range (i386 `jl`/`jg` past a `mov edx,1`, arm32 `blt`/`bgt`, aarch64 `b.lt`/`b.gt`,
x86-64 a shared true-label jump table capped at 128 entries). They do that
because they accumulate in a *register*, so skipping the store needs a branch.
wasm has an operand stack, so the same accumulation is an expression and the
control flow disappears. `check_set.sh` asserts the absence — no `if`, `loop` or
`br` in the lowering — because "we happen to emit no branches today" and "this
construct does not need branches" are different claims and only the second one
survives an edit.

Falsified with four breaks: a range read as a scalar, an exclusive upper bound,
the width choice forced to i32, and an off-by-one on the accumulator's initial
value.

**The four-signature check nearly passed for the wrong reason.** Breaks 1 and 2
printed identical `-` lines. That looked like the failure the rule warns about —
one assertion wearing two names — but the `-` side of a diff is the *native*
build, which is by construction the same for every break. The signatures live on
the `+` side, and there they differ twice over: on the interior of `[2..4]`
(break 1 leaves only 2, break 2 leaves 2 and 3), and again in the opposite
direction on the degenerate range `[3..3]`, which break 1 leaves intact and
break 2 empties. Four breaks, four signatures — but the check that established
that is "read the side of the diff that varies", not "read the diff".

### Two silent wrong answers found by asking how wide the compare should be

Filed on master, neither fixed here — neither is this lane's file:

- **`bug-p-set-membership-item-constant-truncated-to-32-bits`** [P, p25].
  `ParseSetMembershipAST` declares `loVal, hiVal: Integer` between a
  `ParseSetConst: Int64` and an `ASTIVal: array of Int64`. One `var` line, 64-bit
  ends, 32-bit middle. `1 in [4294967297]` is TRUE **on every target**, wasm32
  and x86-64 included.
- **`bug-a-set-membership-truncates-the-test-value-on-32-bit-backends`** [A, p25].
  i386 `mov ecx, eax` and arm32 `mov r1, r0` keep only the low half.
  `4294967297 in [1,2,3]` is TRUE there, FALSE on x86-64, aarch64 and wasm32.

Five targets, every cell run — x86-64 and i386 natively, arm32 and aarch64 under
qemu, wasm32 under node. An earlier note in this session had arm32 and aarch64
"by inspection"; `qemu-arm` and `qemu-aarch64` were on PATH the whole time, and
checking cost one command. **Inspection would have been half wrong**: arm32
answers TRUE on `2^32 in [2^32..2^32+4]` — the correct answer — because the two
defects cancel, while the two *correct* backends answer FALSE.

**And the differential oracle is blind to the first one by construction.** Both
sides of a wasm-vs-native diff are wrong identically, because the defect is
upstream of every backend. This slice's 64-bit row passes and proves nothing
about it.

That is not a fact about `in`. It is **face thirteen**, and it now lives in
`devdocs/dev/differential-probes.md` — *"when two arms share an upstream, their
AGREEMENT carries no information about that upstream"* — with these two bugs as
the worked example, one on each side of the line. It bears directly on this
lane, because **every check in `test/wasm/` is a pxx-vs-pxx diff.** The rule the
doc gives is the one to apply here: *name what the two arms share, and treat
everything above that line as untested by it.* For this suite the shared part is
the entire Pascal frontend, the AST and the IR; what the diff actually tests is
`ir_codegen_wasm32.inc` against the other backends. That is exactly what it was
built to test — but it is not "wasm32 is correct", and the slices should not be
read as saying so.

Kin to face twelve and distinct from it: twelve is blind in one *direction* (an
arena slope sees refcounts too high, never too low), thirteen is blind over a
*region* (everything the two arms hold in common).
**Applying it to this suite, which is the point of a check.** `test/wasm/` was
audited against face thirteen the same day. Four checks — `check_data`,
`check_phase2`, `check_phase3`, `check_phase4` — assert nothing about program
BEHAVIOUR except a native diff; every other check pairs its diff with at least
one absolute claim (`check_managed` five, `check_pal` and `check_wasi` four, and
so on).

The first version of this paragraph said "exactly one assertion each", and that
was wrong: each also prints `ok  .wasm and .wat describe the same module`, from
the shared `wat_oracle.sh` helper rather than from the check's own body, so a
grep of the file misses it and a glance at the file agrees with the grep. It
does not change the conclusion — that line compares the encoder's two output
paths against **each other**, which is pxx against itself and shared even more
tightly than the native diff — but the sentence claimed a count, and the count
was wrong. Fixed here, and in the note the four checks now print.

Those four are diff-only for a defensible reason — they cover Phases 1-4, where
the subject really is the backend and a shared-frontend defect would be a Track P
bug rather than a wasm one. So this is a **scope statement, not a gap**: their
green means *wasm32 agrees with the other backends*, which is what they were
built to say. It does not mean *wasm32 is correct*, and nothing in their output
distinguishes the two. Anyone tempted to cite them for the second claim should
read this paragraph instead.

**Each of the four now prints what it does not claim**, six `..` lines naming
the shared frontend/AST/IR and pointing at face thirteen. That is the cheap
half of the fix: it costs nothing, and it removes the ambiguity without waiting
for a second suite to show the same shape. Accidental coverage and designed
coverage read identically from the outside; a line saying which one this is
turns that back into something a reader can check.

The checks that carry absolute assertions are the ones that can speak above the
IR, and they were added for unrelated reasons — the retain control in
`check_dyn`, the alias control in `check_managed`, the branchless assertion in
`check_set`, the capability claims in `check_wasi`. That they now double as
face-thirteen coverage is luck, not design, and worth noticing before the luck
runs out.

### Phase 9c — the O(n^2) that made the phase unmeasurable — **DONE 2026-08-28**

`WasmText` appended the .wat text with `WFText := WFText + …` once per emitted
instruction. Each append allocates a fresh AnsiString of the whole accumulated
length and copies it: sum(i) for n instructions. `WFText` resets per function,
so the peak was set by the **largest single body** — which is exactly why it
survived eight phases. Every slice in `test/wasm` has small bodies.

| 300 if/else in ONE procedure | peak | wall |
| --- | --- | --- |
| before | 7179 MB | 107.6 s |
| after | **31 MB** | **0.51 s** |
| x86-64, same input | 29 MB | 0.40 s |

Now the grow-by-doubling pool `WasmDataSeg` already used in the same file, with
the AnsiString materialised once per body in `WasmBodyEnd`. All 16 `*_slice.pas`
compiled to .wat by the pre-fix binary (`2e68d018ccac`) and the fixed one
(`966177c0b3f2`) are **byte-identical** — compared against the OLD compiler, not
against the same build, because for a pure accumulation refactor output
preservation *is* the requirement.

**Three synthetics measured reassuringly flat before one caught it, and they were
flat because they varied the wrong quantity.** 3200 procedures: 326 MB. 1600 `in`
expressions: 300 MB. A library-heavy program: 315 MB. Body COUNT was never the
variable; body SIZE was, and the first three tests all held it near zero. A
control that reports "no effect" is only worth what its axis is worth.

**And native-flat-on-identical-input is what localised it**, before a line of code
was read: 30 MB on x86-64 and i386 where wasm32 took 827/3213/7180. The two
mechanisms guessed in the ticket — the encoder holding all bodies, an O(n^2) over
patch sites — were both wrong. Naming neither as the cause is why nothing had to
be retracted.

### Re-measured after `in` and the fix — the row Phase 9b could not produce

`compiler.pas` for wasm32, probe build `c5f9a6672751`, **peak 595 MB, 26.5 s**
(it was 52 GB and did not finish):

| | after 9a | after 9b+9c |
| --- | --- | --- |
| bodies lowered | 3222 of 3650 (88%) | **3494 of 3657 (95.5%)** |
| bodies refused | 428 | **163** |
| refusal lines | 431 | **166** |

| lines | refusal | was |
| --- | --- | --- |
| 75 | `IR_DEFAULT_MEM` (statement IR op 52) | 74 |
| 27 | open-array parameter | 30 |
| 26 | builtin unrecognised (15× -50, 6× -52, 3× -56, …) | 15 |
| 8 | `LoadFile` (-100) | 5 |
| 8 | `Length` of Pointer | 10 |
| 5 | record via `RetViaHiddenDest` | 5 |
| 5 | record in a `PXXMemMove` write argument | — |
| — | **set membership, `in`** | **267 → gone** |

**The promotion effect did not happen this time, and that is worth recording
because last time it dominated.** Removing dynamic arrays sent `in` from 68 to
267. Removing `in` moved `IR_DEFAULT_MEM` from 74 to 75. The first-refusal
caveat says a leader MASKS what is behind it — it does not say how much, and
here the answer was almost nothing, because the bodies blocked on `in` mostly
had nothing else wrong with them. **The caveat names a possible effect, not a
law**, and the honest form of it is that a first-refusal histogram's tail is
*unknown*, not *understated*.

### What the unobtainable-number note said, kept because it was right

### The coverage number for this phase is currently unobtainable, and that is the finding

Phase 9a ended with a re-measurement. Phase 9b cannot have one yet:
`pascal26 --target=wasm32 … compiler/compiler.pas` was observed at **52.1 GB RSS
and still climbing** after 26 minutes, on a 60 GB box with 1 GB left, and it
**SIGSEGVs at 7.6 GB** under an 8 GB cap. Filed as
`bug-wasm-compiling-compiler-pas-for-wasm32-needs-tens-of-gb`.

**It is not the `in` work.** The pre-`in` backend on the same input under the
same cap: 7600540 KB / 144 s, against 7600416 KB / 128 s for the current one.
Identical. Three further controls — 1600 `in` expressions flat at 300 MB, the
same program with `in` rewritten as comparisons *higher* at 1378 MB, and
200/800/3200 bodies at 302/304/326 MB — rule out set density and body count too.
The suspect was mine and the measurement cleared it, which is the only reason
the ticket does not say "probably the new lowering".

Two consequences for how this phase is run:

- **Cap this command.** At 58 of 60 GB the box had no headroom and background
  jobs were being killed — including this lane's own, which read as arbitrary
  harness behaviour for several turns before anyone measured the memory. The
  kills were the *symptom*; `free -g` was the diagnosis, and it was one command
  away the whole time.
- **The phase's own instrument is gated on the finding.** Coverage for Phase 9
  can only be measured when the box happens to have ~55 GB free, so the number
  after `in` is *not recorded here* rather than estimated. An estimate would
  have looked like the 9a row and carried none of its evidence.

### Phase 9d — `IR_DEFAULT_MEM` (op 52), the leader at 75 lines — **DONE 2026-08-28**

A `PXXMemZero` call, the way `WasmEmitCopyRec` already calls `PXXMemMove`.
x86-64's managed-record arm (release the ARC fields, then zero) is guarded but
not implemented: all 14 construction sites pass `REC_NONE`, so it is
unreachable from today's IR. The guard stays — "unreachable by inspection" is a
claim that expires with nothing going red.

`compiler.pas`: **3494 → 3570 of 3658 (95.5% → 97.6%)**, refused 163 → 88, op 52
gone from the histogram.

**The first slice tested nothing, and all three breaks passed it.** It dirtied
memory with `$5A5A5A5A` and called `Take(nil)` from the main body — but
`Dirty`'s frame is DEEPER than main's and never overlaps it, so every temp
landed on memory that was already zero. Deleting the zeroing outright changed
no output. The `One`/`Two`/`Both`/`Twice` wrappers exist to put each temp at
`Dirty`'s own call depth; only then does the break show `data=1515870810`.

That is **face fifteen a third time in one session**, and the axis was different
each time: body size, then a helper's output not being in the file that was
grepped, now one stack frame. Knowing the rule did not prevent it. The header of
`defmem_slice.pas` says so, because the wrappers look like ceremony a later
reader would simplify away.

**Two of the three breaks are still not caught, and the second one led somewhere.**
Halving the byte count is invisible — and the reason is not that the check is
weak. `symtab.inc`'s `EnsureMethodPtrRec` hard-codes `UClsSize_ := 16`, so a
`procedure of object` is declared 16 bytes on every target while a 32-bit
payload is 8; half of 16 still covers all of it. Measured on i386, arm32 and
wasm32; filed as `bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets`
[A, p20], not fixed here — shared file. **A break a check cannot see and a break
that changes nothing observable are indistinguishable from the output**, and
only chasing the second reading found the defect.

### Phase 9e — open-array parameters + `Length of Pointer` — **DONE, 2026-08-29**

Taken as one unit, because every open-array probe refused on `Length`/`High`
before reaching the parameter, so the two classes could not be tested apart.

**Result:** `compiler.pas` reaches **3606 of 3658 bodies (98.6%)**, refusals
88 → 52; open-array 27 → 0, `Length of Pointer` 8 → 2. Covered by
`test/wasm/check_openarr.sh`, wired into `check_all.sh`.

**The parked diagnosis was right that the refusal was stale in its reason, and
wrong about what fixing it needed.** It predicted "not a one-liner" from an
experiment that trapped at run time. The trap was real, but it came from the
*extra* deref that experiment added, not from a layout gap. The landed change
is **twelve lines**: delete the stale refusal, and let `WasmNodeIsDynArray`
answer yes for an open-array parameter so `Length` reads the same header word
the indexing beside it already read. Nothing about the argument paths in
`IRLowerCallArg` needed enumerating.

**What the session nearly landed instead, and why it did not.** The first
working version also widened the `IR_LEA` array arm to take every array
parameter and refined its deref discriminator to `IsRef and (ArrLen = -1)`.
Both were then **measured inert**: with the narrow predicate only `ArrLen = -1`
symbols enter the arm, so the refinement is a no-op, and open-array params fall
through to the generic path that already emits exactly the one deref they need.
Identical `.wat` on all 17 slices, identical 3606/3658 on `compiler.pas`, and —
holding the input fixed and varying only the binary — a byte-identical
`compiler.pas` `.wasm`. The twenty-line rework bought nothing the seven-line
deletion did not.

**A false signal worth recording, because it nearly justified that rework.**
Compiling `compiler.pas` with the two compilers gave *different* `.wasm` bytes,
which read as proof the widening mattered. It was not: `compiler.pas`
**contains the file being edited**, so the two runs differed in their INPUT as
well as their compiler. Face thirteen's shape — two arms sharing an upstream —
except the shared upstream was the source under test. Holding the source fixed
and swapping only the binary produced identical output and settled it. The
general form: **when the compiler is its own test input, a diff cannot tell a
codegen change from a source change.** The determinism control (same binary,
same input, three runs, one sha) is what made the second measurement readable,
and it is worth running *before* trusting any such diff.

**The one shape left out of the slice, deliberately.** An open-array-of-STRING
argument written as a `[...]` **constructor** still refuses — root-caused to
`ir.inc:11207`, not to this backend. An open-array parameter records its
ELEMENT kind in `TypeKind`, and the managed-string arg spill reads that field
without also testing `IsArray`, so the argument is spilled through a hidden
temp declared `tyAnsiString` that actually holds an array data pointer. The
register backends absorb it — the mistyped retain and the scope-exit release
cancel — so **wasm32 is the only target that can see it**. Confirmed by
measurement: adding the `IsArray` guard that the same file already uses at
:11329 removes the refusal and the output matches native. Shared Track A
ground, so it was escaped rather than edited:
`bug-a-open-array-of-string-arg-spilled-through-a-managed-string-temp`.
The slice feeds `JoinOpen` from a dynamic array instead, so
open-arrays-of-managed-elements stays covered and only the constructor
spelling is missing; the check says so in its own "does NOT catch" section.

### Phase 9f — aggregate function results: the hidden destination — **DONE, 2026-08-29**

`abi.inc`'s `RetViaHiddenDest` is ONE convention, not five features: a record,
a set, a variant, a promotable int and a frozen string all come back through a
destination the CALLER allocates and the callee fills. Every register target
carries that pointer in a spare register (x8 on aarch64, r10 on x86-64). wasm
has none and cannot invent one, so here it is a **trailing parameter** — and
that single difference is the whole arm.

Trailing rather than leading so the declared parameters keep their indices: the
body homes parameter *i* from local *i*, and a leading destination would have
shifted every one of them, for exactly the set of procs whose bodies are
hardest to check.

**Result on `compiler.pas`: 3615 of 3660 bodies, refusals 52 → 45.**

**Report what it PROMOTED, not what it removed** — the numbers only reconcile
that way:

| | |
| --- | --- |
| `RetViaHiddenDest` records | 5 → **0** |
| `PXXMemMove` of a record | 5 → **0** |
| `IR_DYNUNIQUE` (`value IR op 49`) | 1 → **4** |

Ten refusals removed, **three promoted** into a gap that was always there and
that only two bodies had previously reached. Net −7. A refusal count is a claim
about what the bodies *reached*.

**The denominator moved too, and it is not a coverage change.** 3658 → 3660
because `compiler.pas` contains the file being edited and this work added two
functions to it. Face eighteen, in the most ordinary possible form: the
body-count denominator is not a constant across a change to this backend, so
"3606 of 3658 → 3615 of 3660" is two different populations and the percentages
are not directly comparable.

**`IR_SET_COPY` came along**, because a set result cannot travel without it — a
32-byte block copy, the same `PXXMemMove` shape as `IR_COPY_REC`. Noted while
writing it: the set width has **no name**. Six backends each write a literal
32, so a change to the set representation would have to be found by grep in six
places. That is a `defs.inc` fix and not this backend's to make unilaterally.

**Three of the five shapes landed UNTESTED, and that is stated in the check
rather than left implied.** A set result additionally needs set CONSTRUCTION
(`value IR op 33`) and `in` against a set VARIABLE (`binary operator 99`);
variant and promotable-int results have their own unimplemented shapes. They
travel by this same convention, so it is live for them and unexercised. An
indirect or virtual call returning an aggregate still refuses **by design** —
`WasmNodeIsAggRetCall` asks about a DIRECT call specifically, so those cannot
silently yield whatever is on the operand stack.

**The bug worth recording, because the compile check was no help at all.** The
first working version put the copy AFTER the epilogue restored `$sp`, on the
reasoning — written into the comment — that every slot is addressed through
`$fp` so a restored `$sp` cannot move them. True of the scalar load beside it,
false of this, because this is a **CALL**: `PXXMemMove`'s own prologue sets its
frame at `$sp`, which once raised lands exactly on top of the Result local
being copied out of. It compiled, validated, reported `125 of 125 bodies
lowered`, ran to completion, and returned `x=3 y=8` — the `y` field holding the
byte-count argument of the memmove that had just overwritten it. Only the diff
against native said so, and the same signature reappears in break 3.

`test/wasm/check_aggret.sh`, wired into `check_all.sh`, falsified three ways:
the copy after `$sp` restore (module dies), `TypeSize` instead of
`AggRetCopySize` (the fixed-array and frozen-string rows go binary), and
returning the callee's own Result slot instead of the caller's destination
(the `y=8` signature again).

### Phase 9g — nested dynamic arrays: `IR_SETLEN_DYN` + `IR_DYNUNIQUE` — **DONE, 2026-08-29**

Taken together because they cannot be tested apart: a nested row has to be
`SetLength`'d before it can be indexed, and every probe for one refused on the
other first.

**Result on `compiler.pas`: 3621 of 3662, refusals 45 → 41.** Promoted, not
just removed: `IR_DYNUNIQUE` 4 → 0 and `IR_SETLEN_DYN` 2 → 0, six gone; **two
promoted** into a newly-reached `value of type record in array base`. Net −4.
Denominator 3660 → 3662 again — two more functions added to a compiler that
contains the file being edited (face eighteen).

**`IR_DYNUNIQUE` is one deref, and `defs.inc:747` still says otherwise.** The
node's own documentation reads *"Write mode: clone-if-shared then load"*. That
stopped being true when `decide-dynamic-array-value-vs-reference-semantics`
settled on matching FPC, where a dynamic array is a reference type all the way
down; x86-64's arm says so at `ir_codegen.inc:5328` and the clone is gone at
every depth. **Implementing what `defs.inc` says rather than what the backends
do would have made wasm32 the only target with value semantics at depth** — a
silent, plausible, target-specific divergence. The stale line is shared ground
and is left alone; the divergence is noted here.

**The bug, and it is the one the neighbouring arm carries a warning about.**
`SetLength(m, 3)` on an `array of array of Integer` does **not** take the flat
`-102` builtin path: it lowers to `IR_SETLEN_DYN` whose target is an `IR_LEA`,
and `IR_LEA` on a dynamic array **auto-loads** to the data pointer, while
`PXXDynSetLen` needs the **slot** and reads a nil handle as "nothing to do".
The first version did exactly that: every body lowered, module valid, `123 of
123`, and `Length(m)` answered **0**. riscv32 shipped the same bug once
(`bug-a-riscv32-nested-dynamic-array-element-write-segfaults`).

Two things about that are worth keeping:

- **The `-102` arm ten lines away carries a paragraph warning about precisely
  this, and reading it did not prevent it.** The warning is phrased about
  `WasmLValueAddr`-vs-`IR_LEA`, and this arm reaches the slot a *third* way. A
  warning is indexed by the shape its author hit.
- **`InLValueWrite` looks like the fix and is not.** It is the mechanism
  `defs.inc` names for exactly this, x86-64 sets it here, and setting it on
  this target changes nothing — the flag is consulted by `IR_LEA`'s
  **managed-string** arm, while the dyn-array arm loads unconditionally and
  deliberately, because every other consumer (including a write target like
  `a[0] := 5`, which indexes into the data) wants the data pointer. Copying the
  register backend's mechanism would have produced code that looks correct,
  cites the right global, and does nothing.

**`check_forwards.sh` caught what the per-fix loop cannot.** The new arm called
`WasmDataAddr` 300 lines before its declaration. pxx resolves across the unit,
so `make compiler/pascal26` — the self-host fixedpoint — passed cleanly; **FPC
resolves in source order, so the BOOTSTRAP SEED would have failed**. That is
the one direction the fixedpoint is structurally blind to, being already past
the seed. Fixed with a `forward;`.

`test/wasm/check_nested.sh`, wired into `check_all.sh`, falsified three ways —
emitting the LEA node instead of the slot address (the silent-SetLength bug),
the symbol's descriptor instead of the node's (riscv32's stride bug), and
dropping `IR_DYNUNIQUE`'s deref. All three trap; the richer slice turns what
was a silent zero in the minimal repro into a hard failure.

**Still refused: `Length(m[1])`**, the length of a nested ROW (2 lines). Its
argument arrives as a bare `IR_INDEX`, whose value is the ADDRESS of the slot
holding the inner handle, where the root case's `IR_LEA` yields the handle
itself — one deref apart, and `WasmNodeIsDynArray` cannot separate them by node
kind alone. Everything else about a nested row (write, read, resize) is covered.

### Phase 9h — the slot arms: `Length` of a field, ARC record copy, arrays of records — **DONE, 2026-08-29**

Three separate ops, landed as one phase because the same misreading produced
all three refusals: **the node's type kind was read as the node's own type when
it describes what the node points AT.**

**Result on `compiler.pas`: 3698 of 3734, refusals 41 → 36.** And the shape of
the remainder matters more than the count: **every one of the 36 is now
blocked, not open.** 35 are the builtins block — `writeELF*`, `writeU8/16/32/64`,
`LoadFile` — waiting on
`decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`
[U p40], and the 36th is `IR_SYSCALL` (value op 54), which is the same
question wearing a different hat. **There is no refusal left that this lane can
act on unilaterally.** The denominator moved 3662 → 3734 across a 370-commit
merge, so the count is not comparable to 9g's without saying so.

| refusal | shape | closed by |
| --- | --- | --- |
| `Length of Pointer` (2) | `Length(b.Bytes)`, `Length(g[1])` — a dyn-array handle in a SLOT | one arm on `IR_FIELD`/`IR_INDEX` at `tyPointer` |
| `statement IR op 46` (1) | `IR_COPY_REC_MANAGED` — copying a record that owns managed fields | the ARC walk, through a new descriptor-cell indirection |
| `value of type record in array base` (3) | `list.Items[i].Off := o` on an `array of TRec` | one exemption for `IR_DYNUNIQUE` in `WasmEmitValueAs` |

**The diagnostics were naming their own answers.** `Length of Pointer` printed
`tyPointer` — which is *precisely the discriminator* x86-64 dispatches this arm
on. `value of type record in array base` printed `record` — which is the
ELEMENT kind of an `IR_DYNUNIQUE` whose value is a pointer. Both messages were
accurate about the fact and pointed away from the fix, and the first one read as
"pointers are not supported yet" for weeks. Recorded as its own face: *when a
diagnostic names a cause, ask whether it is naming the discriminator* — and
prefer refusals that say what SHAPE was seen over what TYPE was found.

**The descriptor cell is the one new mechanism, and it is deliberately not a new
mechanism.** A record's ARC walk is `PXXRecordRetain(recAddr, desc)`, and every
register backend reaches `desc` with a code→data relocation resolved after
`EmitRTTI`. This backend has no code→data fixups at all — it emits addresses
inline — and the blob's offset does not exist while bodies are emitted. So the
descriptor goes through one indirection instead: an 8-byte cell in `Data[]`,
loaded at the use site, filled by `AddDataPtrFix` and resolved by
`WasmFillData`. That is a second CUSTOMER of the existing relocation scheme, not
a second scheme. Registered in `WasmFinishMemory`, the only point that is both
after `EmitRTTI` and before `WasmFillData`.

**The leak probe was decoration until it was falsified, and that negative result
is the most useful thing in this phase.** ARC correctness is invisible in
output: a record copy with the retain/release removed prints exactly what a
correct one prints. The first probe repeated `b := a` in a loop and measured
FLAT at 1032 bytes against a build with the release *deliberately removed* —
because repeating one assignment leaks a REFCOUNT, and a bump pointer cannot see
a refcount. The destination has to own something NEW each iteration for failing
to release it to cost memory. Rewritten that way it reports 18392/2712 against
the broken build and 1032 flat at 1000, 9000 and 50000 against the correct one.

**Two arms are named-and-absent rather than silently dropped.** A record passed
BY VALUE and a FUNCTION returning a managed record both refuse upstream with
`EmitZeroFrameSlot: unhandled target` — the loud arm of
`bug-a-emitzeroframeslot-has-no-wasm32-arm` [A p55], which is Track A's. They
are named in the slice and again in the check's "does NOT catch" section,
because a slice that fails for something that is not its subject stops being a
slice.

**Found on the way, filed and not fixed here:** `rs[1] := s` — a string
assigned to a record ARRAY ELEMENT — compiles clean and segfaults, while the
plain-variable form `r := s` is correctly rejected. FPC rejects both.
`bug-p-a-string-assigned-to-a-record-array-element-is-not-type-checked` [P p60].
It surfaced through a botched line in this lane's own test that the compiler
agreed with; **a test whose bad line the compiler catches teaches nothing.**

### Phase 9i — `EmitZeroFrameSlot`: the probe comes out — **DONE, 2026-08-29**

`bug-a-emitzeroframeslot-has-no-wasm32-arm` [A p55]. **`compiler.pas` now
compiles for wasm32 with no hand-patched compiler.** Every coverage number in
9b through 9h was measured with a temporary probe in `symtab.inc`, reverted
before each commit; that probe is gone and the number is the same — 3698 of
3734, 36 refusals, all blocked.

The ticket asked whoever took it to decide a fork explicitly rather than add an
arm beside a pass that already did the job. **One of the two readings turns out
to be impossible**, which is worth more than the choice:

  * `EmitZeroFrameSlot` writes machine code into `Code[]`, which this target
    never reads; and
  * both callers run from `CompileAST`, which calls `IREmitMachineCode`
    **afterwards** — so when the routine runs there is no wasm body being
    emitted and no cursor to emit into.

Explicit no-op arm, reason at the arm; `WasmEmitManagedLocals` is the owner.
`EmitManagedLocalCleanupForTarget` gets the same on the release side (already a
no-op, since its chain just ends — but an unnamed fall-through is
indistinguishable from an unconsidered one). Three mechanisms for one guarantee
become one mechanism and two arms that say why they are not it.

**THE GAP AND ITS GUARD WERE THE SAME LINE, and this is the finding.**
`WasmEmitManagedLocals` zeroed scalar AnsiStrings and dynamic arrays and
nothing else. Every other managed kind `ManagedLocalZeroBytes` knows about — a
local record with managed fields, a static array of string, a Variant, a COM
interface, a promotable int — was **unzeroed on this target**, and unreachable
*only because the wide chain refused them at compile time*. The loud `Error`
this ticket was filed against was, accidentally, the protection. Removing the
refusal and leaving the pass alone would have shipped a use-after-free in the
same commit that closed a ticket marked harmless. So the zero half now asks the
shared table instead of restating a list; the release half keeps its own
narrower predicate, because *what must start nil* and *what this backend knows
how to release* are different questions and sharing one predicate is what hid
this in the first place.

**Falsified against a build broken on purpose.** With the zero pass removed,
the local-record row dies with `memory access out of bounds` — it releases the
dirty bytes of its unzeroed local as a live string handle. **The plain-string
row still PASSED in that build**, which is the measurement that justifies the
wide-extent rows existing separately rather than trusting one managed local to
stand for all of them. Every row runs after a recursion that writes
recognisable non-zero words into the shadow stack, because all of this is
invisible on a clean one, and `check_zeroinit.sh` asserts those words are still
in the emitted module — a dirtying routine the optimiser folded away would
leave the whole check passing for free.

**Other targets: emitted output byte-identical** for aarch64, arm32, i386,
riscv32 and x86-64, **with a positive control** — perturbing the x86-64 narrow
arm's immediate changes 2 bytes of the same corpus, so five identical results
are evidence rather than a tautology. (The same perturbation breaks the
self-host fixedpoint outright: a second, independent proof of reach.) The first
attempt at that control was itself wrong and is recorded rather than tidied
away: the perturbed build FAILED, `compiler/pascal26` stayed stale, and the
comparison printed "CONTROL FAILED — the corpus never reaches it". **A control
that cannot build is not a negative result**, and reading it as one would have
inverted the conclusion. Re-run as a single generation from a known-good
compiler.

### Three defect-shaped checks expired on the same day

`check_strop.sh` carried the x86-64 string leak's magnitude (401032) as the
number it compared against. `check_managed.sh` asserted the heap base was still
below 1024. `check_calls.sh` asserted the heap had no arena. All three were
written to keep a known defect from being silently encoded, and **all three
encoded it anyway — as the number or the inequality they compared against.**
Each went red the day its defect was fixed, in the direction that reads as a new
regression.

The `exit 1` is what saves the pattern: each one named, in its own failure text,
the paragraph to rewrite. What replaces them is a different KIND of claim, not a
smaller one — the heap checks now assert that the base clears the null guard,
that the arena really holds ~1 MiB and every byte is writable, and that filling
it leaves the module's globals intact. None of them names the arena's address,
which is a BSS-layout accident that would make an unrelated change look like the
bug returning.

- **Milestone:** the wasm-hosted compiler's **emitted output bytes are identical
  to the native compiler's** for the same input.
- **State this claim precisely.** It is output parity across two hosts of the
  same compiler. It is **not** a self-host fixedpoint and must never be written
  as one — see the third row added to the claims table in
  `../wasm-target-findings.md`.

## Phase 10 — browser profile (hand off)

The second import profile (`write` → console, no fs) and a playground. That is
Track W/E work, proposed to the user when Phase 9 is green. Not ours to scope.

## What does not exist under wasm, and is not a defect

Refused by the platform, listed so nobody files a bug: sockets (27 files in
`lib/`+`examples/`+`test/` need them), fork/exec/wait (16 files), mmap (2),
dlopen, cwd, uid/gid/permissions, signals, threads, coroutines.

Threads and coroutines are worth naming twice: `thread_emit.inc` and
`coroutine_emit.inc` are *already* per-target `if` chains that do not emit for
xtensa or riscv32. wasm joins an existing hole at zero cost. It is not a wasm
problem; it is a five-of-six-targets problem.

## Sizing

~7-9k lines, ~85% in new files that cannot destabilize another lane, plus the
two contained shared-file changes above. Bigger than a frontend skeleton,
smaller than the C frontend was.

## Log
- 2026-08-28 — **managed strings, slice 2 (concat + compare) and IR_ATOMIC
  done.** 211 of 236, up from 195. Two of this lane's own checks failed by
  design and both were right to: one listed a refusal that was never load-
  bearing, the other's negative control had been calibrated against a tree the
  change under test invalidated. The leak assertion is the piece worth reusing
  — a leak changes no output, so the slice prints the heap bump pointer's
  advance and diffs THAT against native rather than against a threshold.
- 2026-08-28 — **managed strings, slice 1 (publish) done; the plan's own
  ordering overruled by measurement.** 195 of 236 bodies on the string corpus,
  up from 182, and the single largest refusal cause is gone. Two findings
  outrank the feature: a string-operand guard in `WasmEmitBinop` that was
  reachable only when a DIFFERENT check failed, and therefore was not a guard —
  it let `writeln(t + 'x')` lower to pointer arithmetic on a handle before this
  phase started; and zero-init, which the plan never mentioned, is half of what
  makes a managed slot work at all. Both written up under Phase 8a.
- 2026-08-27 — branch and standalone checkout established; plan and charter
  written.
- 2026-08-27 — Phase 0 complete. Tooling proven (wabt + node, no wasmtime yet),
  the `IR_PROCADDR` question answered favourably, three fall-through chains
  found and handed to Track A. Phase 1 now waits on one thing only:
  `feature-a-wasm32-target-registration-skeleton` landing on `master`.
- 2026-08-27 — **Phase 5 de-risked ahead of schedule.** With Phase 1 gated on
  the registration skeleton landing on `master`, the branch spent the wait on
  the one thing this plan flagged as unproven. Design confirmed against the
  native build; the wabt nesting limit measured; write-up in
  `phase5-exceptions.md`, prototype in `test/wasm/proto/`.
- 2026-08-27 — **re-cut from `master`.** The branch was originally cut from
  `dev`, which had been retired the previous day (collapse `8b2a6bae6`) and was
  379 commits behind. The block on a prerequisite refactor was lifted in the
  same pass: that ticket rested on a premise (`no single answer for pointer
  width`) that measurement disproved. Both caught by frank1-80.
- 2026-08-28 — **Phase 3 (control flow) and Phase 4 (the data segment) done;
  Phase 5 scoped and its shared-file escape dissolved.** The scoping is the
  result worth recording: the escape this plan predicted at
  `elfwriter.inc:1937` is correct for ELF and irrelevant to a target that never
  calls `elfwriter`, and the producer side was target-independent by
  construction all along. Five independent facts had to hold and each was
  checked; the two non-existence claims (`AddMethodFix` is the sole appender,
  `BodyAddr` is never read as an address here) were closed by grepping the
  array and the field rather than the call sites, because **an existence claim
  survives one grep and a non-existence claim does not** — ask what
  construction your search was structurally blind to. Phases renumbered: the
  data segment took the Phase 4 slot it should always have had.
- 2026-08-28 — **Phase 5 (the function table) done.** No shared file touched, as
  scoped. `@Proc`, procvars, VMT slots and RTTI method entries are all table
  indices; index 0 is never handed out, so a nil procvar traps on call for
  free. Two bugs found by building it — a hand-computed section length that is
  right for every module small enough to check by eye, and a write-time
  ordering that is the reverse of the obvious one, because resolving a VMT
  relocation RESERVES a function slot. `gate.sh quick` GREEN on the scoping
  claim and RED on something else entirely: the FPC seed had been broken for
  days.
- 2026-08-28 — **the heap moved ahead of exceptions** (coordinator decision,
  on the lane's measurement). Second reordering of the day with the same cause,
  now stated as a rule rather than an incident. The heap was not a phase at
  all — one line inside the PAL phase — while being the only thing blocking
  class instantiation, `writeln`, variants and the float writers.
- 2026-08-28 — **Phase 6 backend side done; the phase is blocked on one Track A
  ticket.** Casts, `Ord`, `Trunc`/`Round`, `GetMem` and `FreeMem` all lower;
  virtual dispatch, `inherited` and construction match the native build 7 of 7.
  Two findings worth more than the code. First: **my own coverage message was a
  guess** — `needs the heap` on every unlowered builtin, when `PXXAlloc` was
  blocked on an `Integer()` cast and the write path on `Trunc`. I relayed it as
  a measurement. Diagnostics now name the builtin, not a cause. Second: the
  heap allocates **from address 0**, works, passes a 7-value differential, and
  corrupts BSS above ~1 KB — the failure this target's own null-guard note
  predicted in writing and nobody connected until it happened.
- 2026-08-28 — **`writeln` lowers, and a wasm module can reach its host.** The
  second Phase 6 milestone, met on the wasm side and blocked on one shared arm
  exactly as the first was: `writeln` compiled to wasm32 prints under node's
  WASI with output byte-identical to the native build, measured with
  [[bug-a-pxxsyswrite-has-no-wasm32-arm]]'s patch applied locally and then
  reverted. Three findings, in ascending order of what they cost to learn.
  **(1) There was no write codegen to write** — the RTL's target-neutral
  console family already existed for hosted riscv32, carrying the comment "any
  backend could adopt them"; the third time this plan budgeted for work already
  done. **(2) `external 'lib' name 'sym'` IS a wasm import**, and the parser
  had been recording both halves of the name since forever — the second
  predicted shared-file escape to dissolve on inspection, and it dissolved the
  same way the first did: trace the fact to where it is stored rather than
  inferring from the first grep. **(3) The real bug was in the index space and
  it was silent.** Registering an import shifts every defined function's index
  by one, and a module whose indices were baked earlier *still validates* —
  enough signatures match — it just calls the wrong functions. Nothing stores
  an index now; `WasmCall` no longer accepts one. Measured both ways: with the
  relocation removed, a module with an import is rejected with 127 type errors
  and a module without one is accepted unchanged, **which is every suite that
  existed before today.** The `.wat` oracle then caught the same shape one
  level up, in the type numbering — an oracle fed a module from the same
  generator still finds this, because the two encodings disagree about it.
- 2026-08-28 — **Phase 6 complete: a wasm module prints, exits with a code, and
  matches the native build doing both.** `writeln` diffed against native over
  fifteen lines — literals, signed and unsigned, both 64-bit extremes, char,
  boolean, three field widths — read through a hand-written host that decodes
  the iovec AND through node's real WASI on the actual process stdout.
  `Halt(7)` exits 7, agreed by three sources. 105 → **121 of 126 bodies**, and
  three of the five remaining are `IInterface` methods declared without bodies.

  The shared arm this phase was blocked on landed under a **narrow grant**
  rather than by waiting: the evidence offered — the self-host fixedpoint sha is
  identical with and without the patch — *is* the property Track A's
  file-and-wait rule protects, so waiting bought nothing. The grant's condition
  was falsifiable in twelve seconds and was re-verified on the tree actually
  pushed. `HeapMmap` was deliberately NOT granted on the same terms, because its
  fix adds storage and so cannot make the same claim — the line was drawn at the
  strength of the evidence, not the ticket's priority. That distinction is worth
  more than either fix.

  Three things this phase taught that outlive it:

  **A guard that asserts a LIMITATION has to be written to fail when the
  limitation ends.** `check_host.sh` asserted that `writeln` printed nothing,
  and failed on the merge that made it print. That is the assertion tracking
  the delta rather than the outcome, and it is why the replacement differential
  was written in the same hour instead of noticed six weeks later.

  **A check can only gate behaviour its environment does not already supply.**
  Relayed from a sibling lane and immediately true here: `afterWriteln === 0`
  asserted silence, and silence is the default — delete the lowering and the
  assertion still passes. Proven with a negative control that records nothing,
  where every other check in the file stayed green on a compiler that dropped
  every `writeln`. The silence is now asserted together with the mechanism
  meant to produce it.

  **A rule that is slightly wrong reads as complete, which makes it worse than
  no rule.** The forward block said "every routine the dispatchers dispatch to
  belongs here"; the break was a routine that is not a dispatch target, and the
  rule was read while the violating code was written. It is
  `tools/forwardlint.py` now — on master, over the whole `compiler.pas` include
  chain, verified against both historical breaks — and it caught this phase's
  THIRD instance the second it was written, seconds instead of a phase.
- 2026-08-28 — **frozen strings, and the ABI oracle this lane had not been
  asking.** `string[N]`, `ShortString`, the record field and the parameter, all
  diffed against the native build; 123 of 128 bodies. Three findings.

  **The general statement is what made it small.** A frozen string EVALUATES TO
  ITS ADDRESS — the IR's own convention, visible in the x86-64 arm as a bare
  `IREmitNode` — so saying it once in the coercion layer delivered the write
  path, the store path, `Length`, indexing and argument passing together
  instead of five arms that would each have been the one left broken.

  **`abi.inc` already answered the parameter half and this backend was
  re-deriving it.** That file opens by naming the exact shape it exists to
  delete, a `Syms[...].IsRef or` chain inside an `ir_codegen*.inc`, and there
  were two here. The consequence was not cosmetic: a frozen VALUE parameter's
  by-reference convention is flagged on the parameter's SYMBOL and not on the
  proc's declaration record, so `const x: ShortString` reported *no wasm value
  type* — a missing convention wearing a missing type's message. The oracle's
  success metric is that a new pass-by-pointer kind costs one edit; the
  corollary this lane just paid for is that a backend which does not consult it
  gets the wrong answer silently.

  **Two bodies stopped lowering on purpose, and that is the honest number.**
  `PXXVarBinOp` and `PXXVarNot` lowered for an hour by taking a managed
  string's assignment down the scalar path — the slot is pointer-sized, so
  `m := 'lit'` stored the address of a frozen `[len][chars]` blob as if it were
  a heap handle. Validated, ran, and every later read was off by eight bytes.
  It refuses by name now. A count that goes DOWN because a wrong lowering was
  withdrawn is worth more than the count that went up.
- 2026-08-28 — **Phase 7 done: exceptions, nine compositions, 25 lines
  identical to the native build on the first run.** The corpus's own
  `test_exception_finally` and `test_exception_typed` match too.

  **The most valuable thing in the phase happened before any code.** Tracing
  the design against the real IR overturned the prototype's central finding.
  "No runtime handler stack" was true of hand-written WAT, whose nesting is
  visible in the source, and false of the IR, where a `try` emits two
  `EXC_LEAVE`s per `EXC_ENTER` and `EXC_LEAVE n` pops frames the following code
  is still inside. A linear scan reconstructs the wrong nesting and does it
  silently. A conclusion drawn from a simplified input reads exactly like a
  conclusion drawn from the design once it is written down as a finding — which
  is why the correction went into the design doc rather than a commit message.

  **The replacement was cheaper than the thing it replaced**, because `$pc` is
  already a variable feeding a `br_table`: a dynamic landing pad costs what a
  constant one costs. Worth generalising past exceptions — any control transfer
  whose target is data rather than syntax is free in this layout.

  **A check that cannot see a property must assert it directly.** The
  post-call check is gated on `ExceptionUsed`, so a program with no `raise`
  emits no pending flag and no checks. Losing that gate would leave every
  module correct and every call carrying a check that can never fire — which no
  differential can detect, since the output is unchanged. Asserted on a module
  from another suite, and asserted in both directions so the negative cannot
  pass by naming a symbol that no longer exists.

### 2026-08-28 — slice 3: an argument replaced, and an assertion that was vacuous in both directions

**When a check fails on a correct change, the check was doing its job — and
the fix is upstream of the check.** `check_managed.sh` asserted that
`SetLength` and `s[i] := c` still refused, because `IR_LEA` answered HANDLE
unconditionally and that is sound only while no write can reach it. Slice 3
made both lower, so the check went red. Trimming the list to green was
available and would have been wrong twice over: with both entries gone the
*argument* has no support left, and the paragraph above the list would have
gone on claiming a property the build no longer had. Deleting the assertion
without replacing the reasoning is how a design note quietly becomes false.

**Reuse the shared mechanism unless you can say why not.** The position model
is `InLValueWrite` — a global four other backends already use, and one `defs.inc`
names when it states the IR contract for `IR_LEA` and `IR_INDEX`. A private
wasm flag would have been tidier locally and would have been a second,
undocumented contract for the same question. Sharing the mechanism means the
wasm arm reads like the other four to whoever is comparing them, which is the
whole value: this file's neighbours are what a reviewer diffs it against.

**Falsify every mechanism, and record what each break actually broke.** Four
deliberate breaks, four different failures — one caught by exactly two lines of
a twenty-four line slice, one a trap, one a single silent line, one total
silence. Knowing *which* line catches which break is what tells you the slice
covers the mechanism rather than the feature.

**An assertion that passes on first write has not yet been tested.** The
`i32.load`-before-`PXXStrSetLen` grep was vacuous for both shapes it could see
(a global's slot is a constant, a local's is `fp+N`) and would have failed
*correct* code for the one shape it could not (a var parameter's slot address
genuinely is a load). Wrong in both directions simultaneously, and green.
That is the same failure as `check_strop`'s module-wide negative control one
slice earlier: **check what an assertion is quantified over before believing
it**, and prefer the property the diff cannot make over the one it can.

### 2026-08-28 — the PAL seam, and a `|| true` that was covering a real bug

**A suppressed check is worse than a missing one, and this is the cleanest
example the branch has produced.** `check_pal.sh` called `wat_oracle.sh` with
an extra `-Fu` argument the oracle does not accept, so the round-trip compiled
the slice without it, failed, and only stayed green because of a `|| true`
appended to keep the script moving. Making the argument pass through instead
took two lines and immediately turned red on a genuine defect: the WAT
emitter's function identifiers were not injective, and had not been for nine
phases, because every slice until this one happened to contain no overloaded
name. The suppression was written *knowing* it was a suppression — which is
exactly when to stop and make the call work instead.

**"The reader's tool rejects it" is not a property of what you emit.** The
first draft of that fix's comment claimed the failure mode was `call $Foo`
binding to the wrong `Foo`. wat2wasm does not do that — it rejects the
redefinition outright, measured. The honest statement is narrower and still
sufficient: we emit a module whose validity depends on which resolution rule
the consumer happens to use, and we do not get to choose the consumer. Claiming
the worse failure mode would have been the same error this branch keeps finding
in other people's comments.

**Land the seam before the implementation when the seam is what unblocks.**
Nothing behind this backend works — all 87 entries return
`PAL_ERR_UNSUPPORTED`. It was still worth its own commit, because the thing it
removed was not a missing feature but a *parse error*: `uses SysUtils` did not
compile for wasm32 at all. Measuring that (642 of 669 bodies, output identical
to native) took one probe and reordered the whole phase.

**Count what the contract says, not what the file says.** The PAL surface is
87 entry points — the posix and esp backends declare exactly the same set,
diffed rather than assumed, which is what makes "a third backend" a well-posed
job. Three plausible numbers describe ESP's refusals (79 mentions of
`PAL_ERR_UNSUPPORTED`, 67 entry points that can return it, 37 that only ever
return it) and quoting the wrong one is how two documents come to look like
they disagree.

**One naming change broke three checks, and the two that kept passing are the
interesting half.** Making the WAT identifier `name$slot` moved every `(func
$Name` line. `check_managed.sh` matched `\(func \$Make ` with a trailing SPACE
and went red immediately on code that was still correct — the good failure.
`check_index.sh` and `check_strop.sh` matched `\(func \$main\$0` with nothing
after it, so they kept matching by prefix and stayed green — which was luck,
not correctness: the same pattern would also match `$main$01`. The repair is
the same in all three, anchoring on the separator (`\$Make\$`), and it is
worth stating as a rule: **a check that greps emitted text is coupled to the
emitter's naming**, so it should match the whole identifier, not a prefix that
happens to be unique today. A pattern too tight fails loudly; a pattern too
loose passes for the wrong reason, and only the first kind tells you anything.

### 2026-08-28 — the WASI file core, and the mirror of slice 2's bug

**Choose an oracle you did not write.** The obvious way to test the WASI PAL
was to extend `wasmhost.js` with the filesystem calls. That would have been a
shim written alongside the backend it tests, agreeing with it by construction —
and the failure mode of this whole branch is a check that cannot fail.
`node:wasi` is an independent preview1 implementation, so a disagreement is
evidence about the backend rather than about the shim, and it is the only way
the capability model gets exercised at all: there is a real directory to
preopen and paths outside it genuinely cannot be reached.

**Falsify two mechanisms and compare the failures to EACH OTHER.** Removing the
read right and transposing SEEK_CUR/SEEK_END both broke the slice — but they
broke it differently (`read=-1` and EPERM versus a wrong offset and a wrong
tell). Identical signatures would have meant one assertion wearing two names,
with the second mechanism untested. Checking that the failures DIFFER is a
cheap step and it is what turns "the suite went red" into "these two things are
each covered".

**The same defect can arrive from either side.** Slice 2 fixed a string guard
that was never reached, because an unrelated width check succeeded first. This
slice fixed a string guard that was reached for something that is not a string,
because a related check was true of one operand. Both came from asking about
the OPERANDS when the question is about the OPERATION — and the fix is the same
shape both times: split by operator, and key each case on the thing that
actually determines it. A comparison is a string compare because of what is
being compared; a `+` is a concatenation because of what it produces.

**A comment that names the wrong cause is worse than no comment.** The slice
carried a note saying SysUtils was pulled out because its unit-init contained a
frozen concat this target refuses. The trap survived removing SysUtils, so the
note was false — and it was false in the most expensive way, by pointing the
next reader at an innocent dependency. Rewritten to say only what is true.

**Bisect with a pattern you have checked.** The search for that cause spent
several rounds reporting `0` for every input, because `grep -c "main\$2"` in a
double-quoted shell string is `grep -c 'main$2'`, and `$` in a BRE means
end-of-line — so the pattern could never match. Every measurement was of
nothing, and the shape was the same one this branch keeps finding in its own
checks: an assertion that passes (or here, reports absence) for a reason
unrelated to the thing it names. `grep -F` from the start would have cost
nothing.

### 2026-08-28 — `_start`, and a define that was never read

Exporting `_start` (Phase 8e — a WASI command module has to have it, or no WASI
host will start it) turned `check_host.sh` red, and the failure was worth more
than the export.

That check's node:wasi arm called `wasi.initialize`, which node refuses on a
module that exports `_start`. Its comment explained that this was fine because
the caller compiled a *second* module with `-dWASM_NOMAIN`, and that
reactor-ness "is a property of how it is COMPILED, and now it says so".

`host_slice.pas` did not contain the string `WASM_NOMAIN`. The define was inert.
Both builds were the same program, and the arm worked only because *no* module
we emitted exported `_start`, so every one of them looked like a reactor to
node. The comment asserted a property of the build that the build did not have —
the same family as the refusal list that stopped refusing and the assertion that
could never fire, arriving this time as prose rather than as a check.

Three things follow, and the third is the general one:

**The define was made real.** `host_slice.pas` now guards its program body with
`{$ifndef WASM_NOMAIN}`, so the flag empties main and the isolation the arm
needs — path 1's raw `fd_write` tested without path 2 writing to the same fd —
comes from main having nothing to do. Falsified by building without the define:
the arm's exact match against `wasm\n5` then sees the program's fifteen lines
first. The moment the flag became load-bearing, a *second* arm went red, because
it had been relying on the same module still running its body.

**The module is a command and the checks now say so.** All three node:wasi arms
use `wasi.start`. Nothing we emit is a reactor: every wasm32 program has a main
wrapper (const initialisers alone are enough to produce one) and now exports
`_start`, so `initialize` is refused by design rather than by accident. Calling
that refusal a bug and suppressing the export under `-dWASM_NOMAIN` would have
invented a compiler flag to keep a test's framing alive; the framing was what
was wrong.

**An inert flag is invisible from the outside.** A misspelled or unread define
does not warn — the build succeeds and produces a module that is simply not the
one the caller asked for. `-dWASM_NOMAIN` had been passed for weeks and had
never once changed a byte. If a flag is supposed to change the output, the check
that passes it should be able to fail without it; here that took one line and
one rebuild, and it is the only thing separating "compiled with the define" from
"compiled".

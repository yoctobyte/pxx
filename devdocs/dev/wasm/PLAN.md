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

## Phase 8 — the PAL

`lib/rtl/platform/wasi/platform_backend.pas`, sized like `esp/` (1,035 lines).
~35 of ~90 entries implemented, ~55 returning `PAL_ERR_UNSUPPORTED` — the same
deliberate refusal Track S established for ESP, inverted: ESP has sockets and no
files, WASI has files and no sockets. **Heap growth is no longer here** — it
was one line in this section and it turned out to gate everything, so it is
Phase 6 now.

- **Milestone:** a program that opens, writes, reads back and closes a file
  under `wasmtime --dir=.`, and prints to stdout.

## Phase 9 — the anchor: `pascal26` under wasmtime

The compiler itself: single-threaded, file I/O only, no sockets, no fork. It is
the one large program that fits this platform exactly.

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

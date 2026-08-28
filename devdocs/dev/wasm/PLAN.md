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

### What the blocker histogram says about the ORDER of this phase

Measured at `f2c0ca849` against `phase4_slice.pas`, 22 unlowered bodies:

| blocker | count | who |
| --- | --- | --- |
| `IR_CALL_IND` | **9** | 8 are RTL error hooks calling an installed procvar handler — `PXXDivZero`, `PXXOverflow`, `PXXRangeError`, `PXXNilRef`, `PXXInvalidCast`, `PXXVariantError`, `PXXObjRelease` — plus the two interface refcount helpers. **Not user procvars.** |
| `IR_VIRTUAL_CALL` | **1** | `TInterfacedObject._Release`. One, in the whole RTL. |
| `IR_WRITE` + `IR_SLOTADDR` | 5 + 2 | all seven in the float writers |
| heap / `Halt` | 5 | Phase 6 |

**The plan's assumption that this phase is where virtual dispatch matters is off
by an order of magnitude.** The indirect-call table is worth nine bodies, the
VMT path one — and the VMT path falls out of the same mechanism for free.

## Phase 6 — the heap **(moved ahead of exceptions, 2026-08-28)**

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
- **Second milestone:** `writeln` of an integer, diffed against native. That is
  `IR_WRITE` plus `PXXWriteUIntD`, both heap-blocked today, and it is the point
  at which a wasm program can report its own answer instead of being
  interrogated through exports.
- **Scope note.** A bump allocator over linear memory with `memory.grow` and no
  reuse is the classic bring-up answer and is NOT throwaway — it is genuinely
  how a wasm heap starts. But `Free` becoming a no-op is a decision with
  consequences for the RTL's refcounting, so state which allocator is being
  built and why, in the file, at the top. Do not let "temporary" be implied.
- **Still in our own files.** Builtin lowering is backend work; the RTL side is
  Track B's `lib/rtl`, and if this phase needs something there it is a Track B
  ticket, not an edit.

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

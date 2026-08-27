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
      reshaped Phase 4. Grepped `lib/`, `examples/`, `compiler/`: the only code
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
      Phase 6. Install wasmtime before Phase 6 as the reference standalone
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
on `master` first and **the branch touches zero shared files until Phase 4**.
Let the branch do it instead and every `master` merge conflicts in exactly the
hottest files in the tree.

**So the standing rule for this branch: if a phase needs a shared-file edit,
that is a signal to file a Track A ticket and wait — never to make the edit
here.** The two known ones are Phase 4 (VMT fixups) and Phase 5 (exceptions);
anything else appearing on that list is a surprise worth stopping for.

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
  | **2 — values and slots** | no entry cites a *value* op, a non-i32 slot, or a non-i32 signature. Scalar i32/i64/f64 loads, stores, consts, binops, unaries all lower. |
  | **3 — control flow** | no entry cites a control-flow op (`IR_JUMP`, `IR_JUMP_IF_FALSE`, `IR_LABEL` reachability). The `br_table` dispatch exists. |
  | **4 — calls and code addresses** | no entry cites `IR_CALL`, `IR_VIRTUAL_CALL` or `IR_CALL_IND`; the report reads **N of N** for the builtin set. |

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

## Phase 3 — control flow

The `br_table` dispatch loop; the 5 control-flow IR ops.

- **Milestone:** `if`/`while`/`for`/`case`/`goto` all correct, *and* no coverage
  entry cites a control-flow op. This is where the differential probe starts
  earning its keep.
- **Known cap, measured 2026-08-27:** the layout costs one nested `block` per
  basic block, and `wat2wasm` (wabt 1.0.36) SIGSEGVs at ~9000 nesting while V8
  accepts 9015 without complaint. The engine is not the limit; wabt's recursive
  text parser is. Binary emission is unaffected — only the WAT debug oracle is
  capped, exactly where a big function makes you want it. Details and the two
  mitigations in [`phase5-exceptions.md`](phase5-exceptions.md).

## Phase 4 — calls and code addresses **(first shared-file escape)**

Table section + `call_indirect` with type indices. VMT slots and RTTI fixups
resolve to **table indices** instead of the 32-bit code addresses patched at
`elfwriter.inc:1937`. The mechanism is centralized — one fixup list, one patch
site — so this is contained, but it is Track A's shared ground.

- **Requires:** a Track A ticket on `master` and coordination before the first
  edit. Do not start this phase quietly.
- **Milestone:** virtual dispatch, interfaces, procedural variables.
- **From here on, `gate.sh quick` on the six existing targets is mandatory** —
  this is the first phase that can move them.

## Phase 5 — exceptions **(second shared-file escape)**

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
  `call_indirect`, which waits on Phase 4.

## Phase 6 — the PAL

`lib/rtl/platform/wasi/platform_backend.pas`, sized like `esp/` (1,035 lines).
~35 of ~90 entries implemented, ~55 returning `PAL_ERR_UNSUPPORTED` — the same
deliberate refusal Track S established for ESP, inverted: ESP has sockets and no
files, WASI has files and no sockets. Heap growth goes through `memory.grow`,
not `mmap`.

- **Milestone:** a program that opens, writes, reads back and closes a file
  under `wasmtime --dir=.`, and prints to stdout.

## Phase 7 — the anchor: `pascal26` under wasmtime

The compiler itself: single-threaded, file I/O only, no sockets, no fork. It is
the one large program that fits this platform exactly.

- **Milestone:** the wasm-hosted compiler's **emitted output bytes are identical
  to the native compiler's** for the same input.
- **State this claim precisely.** It is output parity across two hosts of the
  same compiler. It is **not** a self-host fixedpoint and must never be written
  as one — see the third row added to the claims table in
  `../wasm-target-findings.md`.

## Phase 8 — browser profile (hand off)

The second import profile (`write` → console, no fs) and a playground. That is
Track W/E work, proposed to the user when Phase 7 is green. Not ours to scope.

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

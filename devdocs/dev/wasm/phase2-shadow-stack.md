# Phase 2 — the value model and the shadow stack

Design work done 2026-08-27 while Phase 1 was gated on the registration
skeleton. **Nothing here is built yet.** It is the reading of the existing IR
and backends that Phase 2 would otherwise do expensively, at the keyboard, with
`ir_codegen_wasm32.inc` half-written.

`PLAN.md` says: *"Model on `ir_codegen_riscv32.inc` (3,891 lines) — same 32-bit
shape, and wasm locals make it easier."* That is right about the frame and wrong
about the values, and the correction is the biggest thing on this page.

## wasm32 is a combination none of the six existing targets has

Measured across the backends:

| target | pointer | 64-bit integer arithmetic | double |
| --- | --- | --- | --- |
| x86-64, aarch64 | 8 | native | native |
| i386 | 4 | `edx:eax` pair | soft |
| arm32 | 4 | `r0:r1` pair | soft |
| riscv32 | 4 | `a0:a1` pair | soft |
| xtensa | 4 | pair | soft |
| **wasm32** | **4** | **native `i64.*`** | **native `f64.*`** |

Every 32-bit target this project has ever had also lacked 64-bit arithmetic, so
"32-bit target" and "lower Int64 into a register pair" have been the same
sentence. For wasm they come apart: pointers are 4 bytes, and `i64.add`,
`i64.mul`, `i64.div_s`, `i64.shl` and `f64.*` are all single opcodes.

**And the IR does not force the pair model.** This was the question worth
answering before writing any code, and it answers well: `Is64BitRISCV32` is a
*backend* function (`ir_codegen_riscv32.inc:445`), as are its arm32 and i386
counterparts. `IRLowerAST` hands the backend an `IR_BINOP` with `IRTk = tyInt64`
intact and each target picks its own representation. wasm32 picks the native one
and emits one instruction.

**So the modelling advice splits in two:**

* **frame, slots, addressing, ABI shape → riscv32.** Same 4-byte pointers, same
  `AOP_MEM` = base + displacement model, same ILP32 record layout.
* **value model → x86-64 / aarch64.** `tyInt64` and `tyDouble` are single
  values, not pairs. Do not port riscv32's 64-bit paths.

What that deletes: `ir_codegen_riscv32.inc:436-915` is one contiguous ~480-line
block — the lo:hi value model, `EmitUDivMod64RISCV32`'s restoring binary long
division (64 iterations, MSB-first), `EmitIDivMod64RISCV32`, the 128-bit
multiply for `{$Q+}` checked overflow, and `EmitBinop64RISCV32`'s carry/borrow
synthesis via `sltu`. wasm needs approximately none of it. Nine
`FindProc('__pxx*')` soft-float call-outs go the same way.

That is ~12% of the closest model backend, and it is the hardest 12% to get
right.

## Two stacks, and the one rule that says which

The backends evaluate expressions into an accumulator with an explicit
evaluation stack — riscv32 emits `addi sp,sp,-8; sw a0,(sp)` around a binop's
left operand and pops it back before the operation.

**On wasm that entire dance is deleted, not translated.** wasm *is* a stack
machine: the operands are already stacked and `i64.add` consumes them. The
expression temporaries need no memory traffic, no slot allocation and no
alignment, and the validator type-checks every one of them.

So the target has two stacks with strictly separate jobs:

| | wasm operand stack | shadow stack (linear memory, off `$sp`) |
| --- | --- | --- |
| holds | expression temporaries | named slots: locals, params, `Result` |
| cost | free | a load/store per access |
| addressable | **no** | yes — this is why it exists |

The rule that decides between them is the one Phase 5 already found the hard
way, and it is worth stating once for both phases:

> **A value goes to a frame slot the moment it must survive a branch, a call's
> exception check, or an `&`. Otherwise it stays on the operand stack.**

This is not a style preference. A `br` out of a block requires the operand stack
to match the block's type, so a value *cannot* survive the branch — codegen that
tries fails `wasm-validate` rather than producing a wrong answer
(`CHARTER.md`, "What wasm is good for as a target").

The `PLAN.md` decision — *all frame slots in linear memory; wasm locals are
scratch only* — stands unchanged and for its original reason: `IR_LEA`,
`IR_SLOTADDR`, `var` params, records and `absolute` overlays all need a real
address, and a wasm local has none. This section refines what the *other* stack
is for; it does not reopen that.

## Frame layout

```
  high    ┌──────────────────────┐
          │ caller's frame       │
   $sp →  ├──────────────────────┤  ← prologue: $sp -= framesize
          │ Result               │  +0
          │ params homed here    │  (address-taken / var / by-value record)
          │ locals               │
          │ spilled temporaries  │  (values crossing a branch or a call check)
  low     └──────────────────────┘
```

* `$sp` is a mutable wasm global; `$fp` is a wasm *local* holding this frame's
  base, set once in the prologue. A local, not a global, because it is never
  addressed and never outlives the frame.
* One decrement in the prologue, one increment at the single epilogue every
  path `br`s to. The Phase 5 prototype demonstrates why that single exit point
  matters: it is what makes the shadow stack impossible to leak on an unwind,
  and `run.js` asserts `$sp` balanced after a run that unwound through two
  frames.
* Slot offsets are compile-time constants folded into the load/store
  immediate — the `AOP_MEM` model maps across unchanged.
* Alignment: wasm load/store carry an alignment *hint*, and a wrong hint is a
  performance note, not a fault — unaligned access is legal and defined. Packed
  records therefore need no special path, which is one fewer thing than riscv32
  has to care about.
* Params arrive as wasm locals. Only the ones that need an address get homed to
  the frame; the rest stay locals. Same analysis every backend already does.
* Stack-limit check under `-g` (`PLAN.md`): compare `$sp` against a reserved
  floor in the prologue. There is no guard page — page 0 is ordinary readable
  memory — so without the check an overflowing shadow stack walks into the heap
  silently.

## `IR_FRAME` — a target limitation, not an open decision

`IR_FRAME` (op 70) backs the FPC-compat intrinsics `get_frame`, `get_pc_addr`
and `get_caller_stackinfo` (`pasparser_expr.inc:4480`,
`pasparser_stmt.inc:5161`). Its contract, from `defs.inc`, is a walkable chain:
`[fp]` = the caller's fp, `[fp + PtrSize]` = the return address into the caller.

**Half of that cannot exist on wasm.** Linking the caller's `$fp` at `[fp+0]` is
cheap and would work. The return address is not merely inconvenient — there are
no code addresses in linear memory at all, and the real return address lives in
the engine's call stack, which the module cannot read by design.

A half-chain gives a backtrace with frames and no symbols. `defs.inc` already
records the right answer for exactly this situation: *"xtensa uses windowed
registers with no such linked chain and Errors at lowering instead of lying with
a plausible-looking pointer."* Do the same, and do not pay a store per call for
a chain nothing can walk.

**The escape, if backtraces are ever wanted:** they are already free from the
other side. `new Error().stack` in the JS host and `wasmtime`'s own backtrace
give real function-level traces with names, which is strictly better than
anything a hand-rolled chain could reconstruct here. That is a Phase 8 /
import-profile matter, not an `IR_FRAME` implementation.

**Settled 2026-08-27, and deliberately NOT filed as a `decide-*`.** A recorded
precedent applied to a materially identical case is derivation, not a new
decision, and Track U is for forks the code and the existing rulings cannot
settle. `defs.inc` already settled this one for xtensa. Spending the owner's
attention ratifying a call the codebase has already made is its own error.

So it is documented here as what it is — **a target limitation**, in the same
voice `defs.inc` uses: wasm has no walkable frame chain, because the return
address lives in the engine's call stack and is unreadable by design; `IR_FRAME`
Errors at lowering rather than lying with a plausible-looking pointer.

This becomes a decision the day a real Pascal program calling `get_frame` has to
work on wasm — with that program named, which is the bar CLAUDE.md's compat
table sets. There is no such program today.

## Revised sizing for Phase 2

`PLAN.md` sizes the whole lane at ~7-9k lines against riscv32's 3,891. Phase 2's
share should come in **below** the riscv32 comparison, not at it:

| | riscv32 | wasm32 |
| --- | --- | --- |
| 64-bit pair model + soft div/mul | ~480 lines | ~0 |
| soft-float call-outs | 9 sites | 0 |
| expression stack traffic | every binop | none |
| register allocation / spills | yes | none |
| **against** | | encoder, LEB128, section layout, block emission |

The savings are real but they are not free money — they move into Phase 1's
`wasmenc.inc` and into the block-structure bookkeeping that a register machine
does not need. The honest summary is that Phase 2 is *smaller and differently
shaped*, not simply smaller.

## Open, and not to be assumed

* **`i32` vs `i64` for pointers in flight.** Pointers are 4 bytes, so `i32` —
  but wasm's `memory.grow` and every address operand is `i32` on memory32, and
  mixing an `i64` index into an address is a validation error, not a silent
  truncation. Wherever the IR mixes a pointer and an `Int64` (pointer
  arithmetic on a 64-bit offset), an explicit `i32.wrap_i64` is required. Find
  the sites before writing the binop paths, not after.
* **Signed vs unsigned division and shifts.** wasm has separate `div_s`/`div_u`,
  `shr_s`/`shr_u`, and `IR_BINOP` carries the signedness — but riscv32's
  `signedOp` parameter suggests the mapping has edge cases (Pascal `shr` on a
  signed Int64 is logical, per `ir_codegen_riscv32.inc:824`). Port that rule
  deliberately; it is exactly the kind of thing that produces a plausible wrong
  value.
* **Division by zero and overflow traps — the pre-check STAYS, and removing it
  would be a semantic change, not an optimization.** wasm `div_s` *traps* on
  divide-by-zero and on `INT_MIN / -1`, where the register targets emit an
  explicit check and raise a catchable Pascal runtime error. A wasm trap is not
  a Pascal exception: it cannot be caught, and it takes the whole module down.
  So the explicit pre-check is the difference between Pascal semantics and
  engine semantics, and it is load-bearing precisely where it looks redundant.
  **Written down here so nobody later deletes it as duplicating a hardware
  check that does not exist on this target.** Model it on
  `EmitDivZeroCheckRV32`.
* **`IR_ALLOCA`.** Legal only where the epilogue restores `sp` from `fp`
  (`defs.inc`). The shadow stack does exactly that, so wasm may be able to
  support it where four other backends currently Error — worth checking, but
  not in Phase 2.

## Log
- 2026-08-27 — written during the Phase 1 gate. The `Is64Bit*`-is-a-backend-
  function finding is the load-bearing one: it is what lets wasm32 use native
  `i64`/`f64` and skip riscv32's hardest ~480 lines.

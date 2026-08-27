# Phase 5 — the exception model, prototyped

**Status: the design in `PLAN.md` is confirmed. The risk line on Phase 5 is
retired.** Prototyped 2026-08-27 on branch `wasm`, before any of
`ir_codegen_wasm32.inc` exists — which is the point. `PLAN.md` called this "the
one design that has not been prototyped" and said to find out cheaply, on a
standalone prototype, rather than after Phase 4 is built on the assumption.
This is that prototype.

Artifacts, all under `test/wasm/proto/`, all runnable now:

| file | what it is |
| --- | --- |
| `exc_proto.pas` | the oracle — Pascal exercising five compositions |
| `gen_exc_wat.py` | hand-compiles that program to WAT under the v1 scheme |
| `run.js` | runs the module under node, asserts two invariants |
| `check.sh` | native build vs wasm build, diffed |

```
$ ./test/wasm/proto/check.sh
ok  $sp balanced at 65536, no exception armed
ok  wasm trace identical to native (22 lines)
```

Nothing here touches the compiler. It validates the **design**, at the point
where changing it is free.

## What was proven

The oracle is a native `pxx` build of `exc_proto.pas`; the subject is the same
program hand-compiled to WAT under the scheme below and run under node. The two
traces are diffed line for line. Five compositions:

| case | composition |
| --- | --- |
| A | normal path through a nested try/finally inside a try/except |
| B | an exception crossing **two** frames, each owning a `finally` |
| C | an exception escaping a `while` loop, with a `finally` in the loop body |
| D | an inner handler that catches and **re-raises** to an outer one |
| E | `break` and `Exit(v)` leaving a try/finally |

Plus two invariants a trace cannot show, asserted in `run.js` after `main`
returns: `$sp` is back at its initial value (the shadow stack did not leak
across the frames that exited by unwinding), and no exception is left armed.

## The scheme, as prototyped

* Every function body is a flat list of basic blocks entered through one
  `loop $dispatch` + `br_table` on an i32 `$label` local — the Phase 3 layout,
  unchanged. Exceptions add **no new control-flow construct**.
* A `raise` is: set `$exc_pending` / `$exc_val`, set `$label` to the innermost
  enclosing landing pad **of this function**, `br $dispatch`.
* After every call: `if (global.get $exc_pending)` → jump to that same pad.
* A `finally` is one block whose successor is a per-finally i32 local, the
  **continuation label**.
* An `except` is a block that saves `$exc_val` into a frame slot and clears
  `$exc_pending`; a bare `raise;` re-arms both from that slot.
* Frame slots live in linear memory off a `$sp` global; `$sp` is restored at
  the single epilogue that every path `br`s to.

## Three things the prototype taught that the plan did not say

**1. The finally continuation is one i32 local, and it absorbs every exit
path.** This is the load-bearing discovery. `normal`, `unwind`, `break`,
`continue`, and `Exit(v)` are not five mechanisms — they are five *values* in
that local. One copy of the finally body, no duplication, no state machine.
Case E exists specifically to show this: `EarlyExit`'s single finally block has
three successors (fall through to after the try, return, and in the loop
version, break) and needs nothing but a different constant.

**2. There is no runtime handler stack, within a function or across one.**
Landing pads are resolved at compile time — at every program point the compiler
already knows the innermost enclosing `try` in the current frame. The only
runtime state in the entire mechanism is two globals and one i32 local per
finally block. Nothing is pushed, nothing is popped, and there is nothing to
unwind, which is why `$sp` cannot leak: the restore is at the one epilogue that
both the normal and the unwind path `br` to.

**3. The post-call check must dominate every use of the call's result — and
wasm's validator enforces this, so it is structure, not discipline.** This was
found by getting it wrong. The first draft emitted
`(call $print (call $Middle (i32.const 1)))`, checking `$exc_pending` after the
result was already consumed, and printed garbage on the unwind path. The fix is
to land the result in a frame slot first, then check. And it is not merely a
convention to remember: a `br` out of a block requires the operand stack to
match the block's type, so a call result **cannot** be left on the wasm operand
stack across the branch the check performs. Codegen that tries will fail
validation rather than produce a wrong answer. Record it as a rule for
`ir_codegen_wasm32.inc`: **a call that can raise ends its expression; its result
is materialised to a slot before the check.**

## One measurement worth having before Phase 3

The scheme costs one nested `block` per basic block, so a function's block count
becomes its control-flow nesting depth. Measured on this box (wabt 1.0.36, node
v22.22.1), with a synthetic function of N blocks:

| N | wat2wasm | wasm-validate | node |
| --- | --- | --- | --- |
| 100 … 9015 | ok | valid | ok |
| ~9030+ | **SIGSEGV** | — | — |

**The engine is not the limit; wabt's text parser is.** V8 accepted 9015 nested
blocks without complaint; `wat2wasm` dies of a stack overflow in its recursive
descent somewhere between 9015 and 9030 (the exact number is stack-dependent,
so treat it as ~9000).

This does not threaten the binary path — `wasmenc.inc` emits binary directly and
we never shell out to `wat2wasm` (`CHARTER.md`). What it caps is the **WAT
oracle**: a function with more than ~9000 basic blocks cannot be round-tripped
through wabt for debugging, exactly when you would most want to. Two mitigations
exist and neither needs deciding now — the relooper `-O` pass already planned for
Phase 3 collapses block counts, and the oracle can fall back to
`wasm-validate` on the binary, which reads binary and is unaffected. Flagging it
so nobody rediscovers it as a mystery segfault at Phase 7, where `compiler.pas`
is the input.

## What is NOT proven, and should not be assumed

Named so the next session does not read "confirmed" as "complete":

* **A raise inside a `finally` while an exception is already in flight.** FPC
  replaces the in-flight exception. The mechanism looks free here (the globals
  are simply overwritten) but it was not exercised.
* **Typed handlers** (`on E: TFoo do`). Orthogonal to this design — a type test
  at the top of the landing pad, re-arming and jumping onward if no arm matches
  — but the *lifecycle of the exception object* is not orthogonal: the
  prototype's exception is a bare i32, where the real one is a heap object with
  a refcount that must survive the pad and be released on handler exit.
* **Exceptions crossing `call_indirect`** — same check, but it depends on
  Phase 4's table dispatch existing.
* **Interaction with the shared-file escape.** This prototype says nothing about
  what `exception_emit.inc` needs to become; it says the target-side design it
  would feed is sound. The Track A ticket is still required before Phase 5
  touches anything on `master`.

## Log
- 2026-08-27 — prototyped and confirmed. Five compositions, 22-line trace
  identical to the native build, `$sp` balanced across unwinds. Three findings
  recorded above; the wabt nesting limit measured at ~9000.

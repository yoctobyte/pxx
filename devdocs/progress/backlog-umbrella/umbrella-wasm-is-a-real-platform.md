---
slug: umbrella-wasm-is-a-real-platform
title: "wasm as a real platform — emit it, and host the compiler on it"
track: A
prio: 25
type: umbrella
blocked-by: [feature-target-wasm, bug-wasm-hosted-compiler-crashes-node-but-not-wasmtime-on-a-full-compile, feature-t-run-the-wasi-slices-under-wasmtime-as-a-strict-second-host, bug-a-emitzeroframeslot-has-no-wasm32-arm, bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps]
created: 2026-08-31
summary: "GOAL, not a unit of work. wasm is named in the goal's platform list and is the non-Unix platform with the most work already landed -- the wasm branch is merged into master. Two halves: emit correct wasm32, and HOST the compiler under a wasm runtime. The hosted half already has a live crash (node, not wasmtime)."
---

# wasm as a real platform

Named in the owner's platform list alongside linux/bsd/minix/gnu/windows. It is
the furthest along of the non-Linux cells: the `wasm` branch is fully merged
into master (verified 2026-08-31).

Two halves, and the second is the one that counts for the goal:

1. **Emit** correct wasm32 from the shared IR.
2. **Host** the compiler under a wasm runtime — the "minimal system with
   compiler" property, on a platform with no processes and no syscalls.

The hosted half already has a concrete failure wired here: the hosted compiler
crashes node but not wasmtime on a full compile, which is a genuine divergence
between runtimes rather than a missing feature.

Full goal: `devdocs/dev/the-goal-cross-cross.md`.

## The gap census, 2026-09-03 - attempted, not triaged

300 sources from the test corpus, compiled for wasm32 with the fixed coverage
report (52d134518), which is the first build whose listing can name more than
one gap per body. 14 programs have a broken body; 278 gap instances behind them:

| count | gap |
| --- | --- |
| 222 | `statement IR op 43` -- **IR_VAR_STORE**, the whole Variant family |
| 18 | `value IR op 54` -- IR_SYSCALL (raw syscalls; wasi has none) |
| 8 | `value IR op 33` -- IR_SET_LIT |
| 7+ | `slot <n> has no wasm value type` |
| 3 | `builtin SetLength (-102)` |
| 3 | `builtin FreeMem (-46)` |
| rest | one or two each: IR_SET_BINOP, IR_RTTI_REG, record loads, `=` on strings |

**Variant is not one of several gaps, it is four fifths of them**, which is why
`bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps` is wired
in here. This is an umbrella grown by ATTEMPTING the target: the ranking came
out of compiling real programs, not out of reading the backlog.

Scope limit: 278 is a FLOOR by construction -- a body stops at its first refusal
-- so the tail is understated relative to the head. It cannot overstate op 43.

## Where it stands, 2026-09-04 (frankA)

Same 300 sources, same report, re-run after each fix. **278 -> 22 gap
instances, 14 -> 5 programs.**

| count | gap | owner |
| --- | --- | --- |
| 18 | `value IR op 54` -- IR_SYSCALL | **filed**, `bug-n-the-nilpy-pal-issues-raw-syscalls-so-every-file-body-traps-on-wasm32` |
| 1 | `value IR op 32` -- IR_RTTI_REG, in `GetClass` | open |
| 1 | `load through a pointer of type record` | **filed**, `bug-a-wasm32-refuses-a-load-of-an-interface-valued-record-field` (DO NOT WIDEN the aggregate-address family: an interface is spelled `tyRecord`) |
| 1 | `string operand of type QWord` | open |
| 1 | `` `=` on strings `` | open |

Eighteen of the twenty-two are the NilPy PAL's raw syscalls, which is a
ROUTING question and not a codegen one -- an IR_SYSCALL arm for wasm32 cannot
be written, because wasi has imports rather than syscall numbers, and
`lib/rtl/platform/wasi` already exists while `compiler/builtin/pypal.pas` has
no platform conditional at all. **So the codegen tail on this target is four
instances in three shapes, in two programs**: `lib_base64.pas` (`GetClass`,
and `pystr_is_none` for both string rows) and `test_assign_lvalue_shapes_ok.pas`.

### THREE CORRECTIONS TO THE NUMBERS THIS SECTION PUBLISHED YESTERDAY

All three are mine, all three are in how the report was COUNTED rather than in
the report, and they are written here rather than silently overwritten because
the wrong figures were quoted to two peers.

1. **`26 gap instances` counted two lines the report itself labels `not a
   coverage gap`.** A declaration-only stub -- `_Unwind_Backtrace`, `getenv` --
   prints under its own heading (`N declaration-only stub(s) trap if called`)
   in the same indented shape as a real gap, so a grep keyed on the shape
   matched both. The row was in the table, correctly labelled; the HEADLINE
   number was not. 26 was 24, and it is 22 today.
2. **`19 IR_SYSCALL` was 18, and always had been.** Every saved census output
   from this arc says 18. Nothing changed; the number was mis-copied once and
   then carried forward.
3. **`value IR op 32` was never listed at all.** It is IR_RTTI_REG in
   `GetClass`, present in every census output back to the first, and it is the
   one remaining shape nobody has looked at. The two errors above cancelled in
   the total, which is exactly why neither showed up in a sanity check of the
   sum: 19 + 0 = 18 + 1.

The lesson is the cheap one and it is worth the four lines: **bucket a report by
running the tool over it, not by reading the buckets off the screen.** The sum
agreed with the previous sum on every re-run, and two of the six rows were
wrong throughout.

Closed to get here, each with a cross row wired against the x86-64 build of
the same source:

- Variant (`IR_VAR_STORE/BOX/BINOP`) -- 222 instances, four fifths of the
  original census. Note it did NOT move the program count at all (14 -> 14):
  a body count and a gap count are different measurements, and only the second
  could show a 75% reduction.
- Sets -- literal, binop, compare, and `x in s` over a real set, each of the
  last three invisible until the one in front was fixed.
- By-value aggregate parameters -- every record of 8 bytes or less and every
  by-value set parameter. An ABI decision, not a missing arm: a wasm parameter
  is one typed local, so there is no "push the bytes" for this target and the
  choice is a private copy or nothing.
- `IR_VMTADDR` -- interface `is`/`as`. Found by running a peer's test, not by
  this census: nothing in 300 corpus sources casts to an interface.
- Aggregate returns through an indirect or virtual call.
- Calls through a METHOD POINTER (`99fa70c34`). The IR already carried the
  answer -- `IRC` on `IR_CALL_IND` is documented as *extra leading Self args* --
  and this backend was the only one that had to read it, because it is the only
  one whose call sites are checked against a type.

**`builtin FreeMem (-46)` LEFT THE TABLE WITHOUT ANYONE FIXING FreeMem**, and
that is the finding rather than the row. wasm32 has had a working FreeMem arm
throughout; `WasmEmitFreeMem` exits False on its own `if WasmBodyBroken then
Exit`, so once the method-pointer refusal above it in the same body had
latched, the arm reported itself and the caller named it. The report now names
a builtin only while the body is still unbroken (`99fa70c34`). A second gap
standing behind a first is usually the next real one -- it was, four times in
this arc -- and it can also be a ghost of the first, so the test is whether it
survives fixing the one in front.

**Two findings on OTHER targets came out of tests written for this one**, which
is the argument for cross rows over wasm32-only ones:
`bug-a-a-parameter-after-a-by-value-set-parameter-reads-zero-on-xtensa` (fixed,
`724e04ea6` -- a by-value set parameter carried only its first four bytes) and
`bug-p-member-access-on-a-procedural-variable-call-result-is-rejected` (filed).

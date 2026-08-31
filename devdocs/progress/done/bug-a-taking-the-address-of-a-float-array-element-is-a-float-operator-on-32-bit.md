---
slug: bug-a-taking-the-address-of-a-float-array-element-is-a-float-operator-on-32-bit
track: A
prio: 50
type: bug
blocked-by: []
status: done
found: 2026-08-30
owner: frankS
summary: "FIXED 2026-08-31 (3c4b50014). The hypothesis in the body was RIGHT and the scope was not: an IR_INDEX/IR_FIELD/IR_LEA node's IRTk names the type AT the address it computes, so every backend's binop dispatch read `@V[0]` as a float operand. The 32-bit compile error is the MILD half -- on x86-64 at -O0 the same defect emitted an addsd of the ADDRESS reinterpreted as a double, silently, returning the right answer only because a finite double plus 0.0 is bit-preserving and an address is a tiny denormal; at -O1+ an imm-fold arm keyed on the NODE type masked it. One shared oracle, IRValueKind in ir.inc, replaces the per-backend question. wasm32 already had the rule privately. Positive control: pinned emits 10 float instructions in the probe at -O0, fixed emits 0."
---

# Taking the address of a float array element is a float operator on the 32-bit targets

- **Type:** bug — **Track A** (the 32-bit backends' float lowering).
- **Found:** 2026-08-30 by frankA, while building a data-alignment regression
  test for
  [[bug-a-a-double-typed-const-misaligns-the-next-const-array-in-the-data-section]].
  The test wanted an `array of Double` row and could not have one.

## Repro — three lines, no float operation in it

```pascal
program p;
var V: array[0..1] of Double;
begin writeln(PtrUInt(@V[0])); end.
```

```
$ pascal26 --target=riscv32 p.pas /tmp/p
pascal26:3: error: target riscv32: unsupported float operator
$ pascal26 --target=i386 p.pas /tmp/p
pascal26:3: error: target i386: unsupported float binop
$ pascal26 --target=arm32 p.pas /tmp/p
pascal26:3: error: target arm32: unsupported float binop
```

x86-64 and aarch64 compile and run it. A `const` array of `Double` fails
identically; the `var` form is shown because it removes typed-const data
handling from the picture entirely.

## Controls, in both directions

Measured at `4cec00985`, self-hosted binary `aa78a7faf63a`, target riscv32:

| program | result |
| --- | --- |
| `var V: array of Double;` declared, never referenced | **OK** |
| `V[0] := 1.5` — actual float work, no address taken | **OK** |
| `@V` — address of the WHOLE array | **OK** |
| `@V[0]` — address of an INDEXED element | **FAIL** |
| `@V[0]` where V is `array of Int64` | **OK** |
| `@V[0]` where V is `array of Single` | **FAIL** |
| `@D` where D is a scalar `Double` | **OK** |

So it is neither "floats are broken on 32-bit" (assignment works) nor "`@` is
broken" (whole-array and Int64-element forms work) nor "arrays are broken". It
needs **both** a float element type **and** an index. That pair is the defect's
shape, and the two OK rows either side of it are what make it a shape rather
than a guess.

## Where it is raised, and the part that is NOT yet verified

`compiler/ir_codegen_riscv32.inc:1075`, the tail of the softfloat binop
lowering — the `else` after the `tkPlus/tkMinus/tkStar/tkSlash/tkEq...` chain
that picks a `__pxx_d*` / `__pxx_s*` helper. Siblings:
`ir_codegen_arm32.inc:2007`, `ir_codegen386.inc:2579`. (`ir_codegen_xtensa.inc:1164`
is the same construct and is presumably exposed too; **not measured** — xtensa
does not run on this host.)

**The mechanism below this line is a hypothesis, not a measurement.** The
plausible reading is that `@V[0]` lowers to a base+index*stride BINOP whose
result type is inferred from the ELEMENT type, so an address computation — pure
integer arithmetic — is dispatched to the float path, arriving with an operator
that path has no helper for. That is a guess from the raise site's shape. It
has not been confirmed against `PXXDBG=a.ir:<proc>`, which is the cheap way to
settle it and the right first step for whoever takes this
(`devdocs/dev/debugging-playbook.md`: do not theorise about an inferred type,
print it).

## Why this is not Track F

Rank the mechanism, never the datatype. The subject is address computation and
operator dispatch; the observable is a **compile failure on valid Pascal**, and
the program contains no float arithmetic at all. CLAUDE.md is explicit that a
missing function a working program calls, or a control-flow/codegen bug that
merely lives in float code, stays an ordinary bug in its own lane —
and that when it is a close call it is NOT F. This one is not close: fixing it
changes no digit of any float result.

## Cost

Small but real, and larger than it looks because it is silent until you cross-
compile. Any 32-bit program that takes the address of a float array element —
passing `@Coefs[0]` to a routine, a `PDouble` walk over a table, an FFI hand-off
— does not build, on three of six targets, with a diagnostic that names floats
in a program that does no float arithmetic. It also blocks the float rows of
[[bug-a-a-double-typed-const-misaligns-the-next-const-array-in-the-data-section]]'s
regression test, which is how it was found; that test ships with Int64 and
Cardinal elements and a note to add the float rows when this closes.

## Gate

`make compiler/pascal26` + the repro above compiling for i386, arm32 and
riscv32, plus the Int64 and whole-array controls staying green. Add the float
rows to `test/test_const_array_align.pas` as part of the fix — the test already
carries the comment saying why they are absent.


## 2026-08-31 — FIXED, and the compile error was the mild half

`3c4b50014`. The ticket's hypothesis was correct and its scope was not.

### What was actually wrong

`IR_LEA`, `IR_FIELD` and `IR_INDEX` all compute an ADDRESS, and their `IRTk`
carries the type of what **lives at** that address — correctly, because that is
what the `IR_LOAD_MEM` stacked on top needs to know. Measured:

```
0: lea   a=95 tk=17 [sym=V]          <- tyPointer
1: const_int ival=0
2: index a=0 b=1 ival=8 tk=19        <- tyDouble: the ELEMENT type, on an ADDRESS
3: const_int ival=4294967295 tk=16
4: binop a=2 b=3 c=30 tk=16          <- `and`, with a "float" left operand
```

Every backend's binop dispatch asks *"is either operand a float"* as
`TypeIsFloat(IntToTypeKind(IRTk[operand]))`. Node 2 answers yes. So a pure
address computation was dispatched into the float lowering, arriving with an
operator that lowering has no kernel for.

The fix is one shared oracle, `IRValueKind` in `ir.inc`, asked by all six
backends instead of each reading `IRTk` directly. **This was not a new idea:**
`ir_codegen_wasm32.inc` already had the rule privately, as
`WasmNodeResultType`'s `IR_LEA, IR_FIELD, IR_INDEX : tyPointer` arm. Two
mechanisms serving one concept is exactly the smell
`normalise-dont-special-case.md` names, and the wasm arm is now an instance of
the general rule rather than a second one.

### The half the ticket did not know about: x86-64 miscompiles this, silently

The report is three 32-bit targets failing to compile. That is the **mild** end.

On x86-64, `PtrUInt(x)` lowers to `x + 0` rather than `x and $FFFFFFFF` — and
`+` **is** in the float set. At `-O0`, `writeln(PtrUInt(@V[0]))` compiled to:

```
movq     xmm1, rax        ; the ADDRESS, reinterpreted as a double
cvtsi2sd xmm0, rcx
addsd    xmm0, xmm1       ; floating-point add of an address to 0.0
movq     rax, xmm0
```

It returns the right answer. A finite double plus `+0.0` is bit-preserving, and
an address is a tiny denormal, so the round trip through the FPU happens to be
the identity. **Wrong code, right answer** — and under DAZ, or for any bit
pattern `addsd` does not preserve, the luck runs out.

At `-O1` and above it is not even emitted: an imm-fold arm
(`ir_codegen.inc:7063`) keyed on the **node's** type rather than the operands'
catches `binop(x, const, ALU-op)` first and emits `add rax, 0`. So on the target
everyone develops on, the defect was absent at the default level and
correct-by-luck at the one level where it existed. That is why a bug reachable
in three lines of valid Pascal survived.

**The generalisable bit:** the 32-bit targets did not have a *different* bug.
They had the *same* bug with **no masking arm and no denormal luck**, which is
the only reason anyone saw it. A target with fewer optimisations is an
instrument, not a liability.

### Positive control

Same source, procedure `Q`, x86-64 `-O0`, two compilers:

| | float instructions in Q (`addsd`/`movq xmm`/`cvtsi2sd`) |
| --- | ---: |
| `pinned` (pre-fix) | **10** |
| this compiler | **0** — the body is pure integer |

And on the 32-bit side the control is the compile itself: `pinned` still refuses
`test/test_float_elem_address.pas` outright (`unsupported float operator` /
`unsupported float binop`) where this compiler runs it.

### Verified

Five targets — native, i386, arm32, riscv32, aarch64 — every row correct:
double stride 8, single stride 4, Int64 stride 8, whole-array 0, scalar 0, and
float add / div / single mul / compare / int-operand `/` all exact.

**xtensa took the same edit and is NOT verified** — it does not run on this
host, which is what the ticket already said about it.

### Tests

- **`test/test_float_elem_address.pas`**, new, wired into `test-core` at the
  default level, **at `-O0`**, and on the four cross targets. The `-O0` row is
  the deliberate part: a default-level native run **could never have failed**,
  and a test that cannot fail is not a test.
- **`test/test_const_array_align.pas`** gains the float rows its own comment had
  been holding open for this ticket (`checked=5` → `7`). Those two rows carry
  alignment coverage the Int64 rows could not: they are the only ones whose
  element type reaches the type-directed half of address lowering. `Single` is
  asserted at 4, not 8, for the same reason `Cardinal` is.

`gate.sh quick` GREEN at `eeb4cfd6cc2a`.

### Left open, deliberately

The **64-bit dispatch** in the 32-bit backends has the same shape —
`Is64Bit(IntToTypeKind(IRTk[left]))` — so `@W[0]` over an `array of Int64` is
still dispatched as a 64-bit operation on a 32-bit address. It produces the
correct answer today (verified: stride 8 on all three), because the low word is
right and the high word is discarded, so this is a cost question and not a
correctness one. Changing it would alter a working path with no measured
benefit; noting it here rather than folding it in silently.

## Log
- 2026-08-31 — resolved, commit b3a6cddc0.

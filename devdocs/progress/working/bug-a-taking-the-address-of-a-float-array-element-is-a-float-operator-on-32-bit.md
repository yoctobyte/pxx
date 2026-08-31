---
slug: bug-a-taking-the-address-of-a-float-array-element-is-a-float-operator-on-32-bit
track: A
prio: 50
type: bug
blocked-by: []
status: working
found: 2026-08-30
owner: frankS
summary: "`@V[0]` where V is an `array of Double` or `array of Single` fails to COMPILE on i386, arm32 and riscv32 -- `unsupported float operator` -- in a program containing no float operation. The element type routes an ADDRESS computation into the softfloat binop lowering. `@V` (whole array) is fine, `@V[0]` on an `array of Int64` is fine, and real float work (`V[0] := 1.5`) is fine, so it is the indexed-address path specifically."
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

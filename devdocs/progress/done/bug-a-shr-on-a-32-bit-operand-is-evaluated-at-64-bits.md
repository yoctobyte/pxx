---
slug: bug-a-shr-on-a-32-bit-operand-is-evaluated-at-64-bits
title: "`shr` on a 32-bit operand is evaluated at 64 bits — `i shr 1` for i = -8 gives 9223372036854775804, FPC gives 2147483644"
track: A
prio: 40
resolved: 2026-08-31
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-28
summary: "MOSTLY NOT A BUG — measured 2026-08-31. Rows A and C are decide-shift-operator-promotion-width working as the user ruled on 2026-08-10 (shifts happen at NATIVE width; --strict-fpc reproduces FPC on all eight rows and does, verified), and row C is row A narrowed by the STORE, which the ruling documents. What WAS a bug is the half this ticket found by accident: an UNTYPED LITERAL shift ran at the target width, so `1 shl 40` was 256 on i386/riscv32/wasm32 and 0 on arm32 while `const K = 1 shl 40` was 2^40 in the same program. Fixed in 243ff4a29. The residual is a Track U re-confirmation the ruling asked for and never got, carried to decide-shift-native-width-was-never-re-confirmed-on-the-full-table."
---

# Repro

```pascal
program ShrProbe;
var i: Integer;
begin
  i := -8;
  writeln(i shr 1);            { A }
  writeln((-8) shr 1);         { B — untyped constant, genuinely 64-bit }
  i := -8; i := i shr 1; writeln(i);   { C }
end.
```

| | fpc 3.2.2 | pxx x86-64 |
| --- | --- | --- |
| A `i shr 1`, i: Integer | 2147483644 | **9223372036854775804** |
| B `(-8) shr 1`, untyped constant | 9223372036854775804 | 9223372036854775804 |
| C `i := i shr 1` | 2147483644 | **-4** |

B agreeing is the control: for an untyped constant the 64-bit answer is
correct, and pxx gets it right, so the shift itself is fine. A and C are the
same expression on a declared `Integer`, and they disagree with FPC *and with
each other* — C is A truncated to 32 bits by the store (0xFFFFFFFC = -4).

# Why it matters

`shr` on a signed value is not exotic — it is how hash mixers, bit-packing and
checksum code are written, and every such loop over a negative or high-bit-set
Integer silently produces a different number than FPC does. Nothing warns. Per
CLAUDE.md's compat table this is the silent-wrong-behaviour escape: real Pascal
source compiles and runs wrong, so it is a bug in its lane, not a compat item.

# The rule being missed

Pascal's `shr` is a **logical** shift performed at the width of the left
operand's type. There is no arithmetic right-shift operator in the language to
confuse it with. So the operand needs zero-extension to its declared width
before the shift, or the shift needs to happen at that width.

Note that C's `i := i shr 1` case shows the two halves are independently
wrong-ish: the store truncates correctly, the shift does not narrow first. Fix
the shift; do not "fix" it by relying on the store, because A has no store.

# Found

By the wasm32 backend, 2026-08-28, while building the Phase 2 differential.
wasm has separate `i32.shr_u` and `i64.shr_u` instructions and no implicit
promotion, so the backend has to choose a width and chose the operand's — which
made it disagree with the native build and agree with FPC. Same root shape as
[[bug-a-function-result-assignment-does-not-narrow-to-the-result-type]]: a
value's declared width is not enforced where a 64-bit register makes enforcing
it optional.

Blast radius beyond the lane: `test/wasm/phase2_slice.pas` keeps its shift
operands non-negative so the lane's gate does not go red for this. Above zero
the two widths agree; the coverage of the instruction is real, the coverage of
the semantics is not, and it cannot be until this closes.

---

## 2026-08-31 — measured: two of these three rows are the RULING, and the third was a real bug, now fixed (frankC)

The repro is right and the numbers are right. The reading is not: rows A and C
are `decide-shift-operator-promotion-width` working as ruled by the user on
2026-08-10, and the ticket was filed without finding that ruling.

> "pxx truncating to 32-bit is wrong (unless we explicitely specified 32 bit).
> but, i'd also say, let FPC do what they think is wrong or right, and (for now)
> we do what we think is wrong or right, BUT, in strict_FPC mode we _will_ copy
> their bugs." — user, 2026-08-10

Both rows were tabulated as costs of that ruling on 2026-08-11 (the "COST of
this ruling, corrected" section of the decision file) — `i shr 1` = 
9223372036854775804 against FPC's 2147483644 is row 1 of that table, verbatim.
Measured at HEAD, `--strict-fpc` reproduces FPC on all eight rows of the
extended probe, which is the escape the ruling promised and it works.

Row C is not a third answer either: it is A stored into an Integer, and the
ruling widens the SHIFT while the STORE narrows as it always did. The decision
file says so in as many words — the RTL survived the change "because their
intermediates land in `LongWord` variables and the STORE narrows".

### What WAS a bug here, and it is the half the ticket found by accident

The ticket's real discovery is in its last paragraph: **wasm32 disagreed with
the native build.** That was not the ruling. Measured across every target:

| | x86-64 | aarch64 | i386 | arm32 | riscv32 | wasm32 | fpc |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1 shl 40` — was | 2^40 | 2^40 | **256** | **0** | **256** | **256** | 2^40 |
| `(-8) shr 1` — was | 2^63-4 | 2^63-4 | **2147483644** | **2147483644** | **2147483644** | **2147483644** | 2^63-4 |
| both — now | 2^40 and 2^63-4 on all six | | | | | | agrees |

(Six measured — x86-64 and i386 native, arm32/aarch64/riscv32 under qemu,
wasm32 under wasmtime. **xtensa is NOT measured**: it is bare metal and nothing
here runs it. It shares the 32-bit typing path, so the fix should reach it, and
that is an inference, not a measurement.)

Untyped literals, on the targets `a3f51dce1` dismissed with *"the 32-bit targets
need no change — native there IS 32 bits"*. True of a declared variable, which
has a width to preserve; false of a literal, which has none. Two 32-bit targets
answering 256 and 0 for the same source is not a width model, it is the
hardware's undefined shift leaking out — and `const K = 1 shl 40` in the SAME
program answered 2^40 on all of them, because ConstEval is Int64 everywhere.
`1 shl 40 = 0` is the trap the 2026-08-10 ruling was made to remove, and it was
still standing on four of the six measured targets.

Fixed in `243ff4a29`; `test/test_shift_literal_width.pas` guards it, and its
assertion IS target-independence.

So the wasm32 backend "choosing the operand's width and thereby agreeing with
FPC" was two things at once, and only one of them was a defect: for a DECLARED
Integer it was right (wasm32 is a 32-bit target; native there is 32), and for an
untyped literal it was wrong along with i386, arm32 and riscv32.
`test/wasm/phase2_slice.pas` can stop keeping its shift operands non-negative
for the literal cases; the declared-operand caution stands, because the ruling
really does make x86-64 and wasm32 differ there.

### The residual, and who owns it

Rows A and C stay divergent from FPC by design, and this ticket is the second
time an agent has hit that in the wild and read it as a defect. That is evidence
about the ruling, not about the code — and the ruling's own author asked for it
to be re-confirmed on the full table and never was:

> "the call is worth re-confirming rather than assuming."
> — decide-shift-operator-promotion-width, 2026-08-11

Carried to `decide-shift-native-width-was-never-re-confirmed-on-the-full-table`
so it has a slug the ranker can see, instead of a paragraph inside a file in
`decided/` that by construction nobody re-opens. **Resolving this ticket closes
the bug, not the question.**

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.

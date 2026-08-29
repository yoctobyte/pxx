---
slug: feature-opt-a64-loadvar-destination-register
track: A
prio: 55
type: feature
blocked-by: []
summary: "EmitLoadVarA64 hardcodes x0, which is why the aarch64 leaf-operand collapse (1185b3489) could only do the CONST half. Giving it a destination-register parameter unlocks the LEAFSYM half — a further 12.6-16.3% of every integer binop on the target. Filed rather than smuggled into the port because duplicating the helper is the second-path failure this repo has a document about."
status: new
---

# `EmitLoadVarA64` needs a destination register

`1185b3489` collapsed aarch64's per-binop `push / eval / mov / pop` dance for a
**constant** right operand. The measured population it left behind:

| program | integer binops | CONST (done) | LEAFSYM (this ticket) |
| --- | --- | --- | --- |
| `compiler.pas` | 54056 | 80.9% | **12.6%** |
| mandelbrot | 4953 | 77.7% | **16.3%** |
| chess | 4917 | 77.7% | **16.0%** |
| jsondemo | 8016 | 77.9% | **16.0%** |

Measured with `PXXDBG=a.a64binop`, which is already in the tree.

## Why it was not done in the port

x86-64's arm loads the right operand **straight into `rcx`** while the left sits
in `rax` — `EmitLoadVarRcx` is a real second entry point. aarch64 has no
equivalent: `EmitLoadVarA64` hardcodes `x0`, and it is not a thin function. It
carries

- the `-O3` unified residency arm (`mov x0, x19..x24`),
- the float-residency arm (`fmov x0, d8..d13`),
- the dynamic-array-handle guard, whose *absence on the load side* was itself a
  segfault (`bug-a-i386-and-aarch64-dynamic-array-assignment-has-no-store-arm`,
  and see the comment in the function — it is the worked example of a double
  case fixed on one arm only),
- size/sign extension per `TypeKind`.

Duplicating that into an `EmitLoadVarX1A64` twin would create exactly the second
path that `devdocs/dev/normalise-dont-special-case.md` exists to prevent, and
the dyn-array comment sitting inside the function is the proof that this
particular helper is one where the arms *do* drift apart.

The cheap-looking alternative — evaluate left, `mov x1, x0`, load right into
`x0`, and let the op read the operands reversed — is only valid for commutative
ops, so it would either exclude `sub`/`div`/shifts or need reversed encodings
per arm. That is a second path in a different costume.

## What to do

Give `EmitLoadVarA64` a destination-register parameter and thread it through
every arm — residency, float residency, dyn-array, extension. Keep the existing
name as a one-line wrapper passing 0 so the ~dozens of existing call sites are
untouched, then add the `LEAFSYM` arm to the binop path alongside the `CONST`
one it already has.

**The extension arms are the risk**, not the residency ones: several encode the
destination implicitly in the opcode constants (`$93401C00` style), so a
register parameter has to reach into each encoding rather than be OR-ed in
uniformly. Budget the review for that, not for the plumbing.

## Gate

Track A: `make compiler/pascal26` (self-host fixedpoint) plus the aarch64
differential against a pre-change compiler — `10 programs x -O0/-O2/-O3` under
`qemu-aarch64`, which is the harness `1185b3489` used, and it must report the
count of pairs it compared. Land behind `-O3` and promote per the campaign rule.

## Note on measuring it

Do not expect a trustworthy timing number on this box: `qemu-aarch64` does not
model store-to-load forwarding, which is most of what removing two stack ops per
binop is worth, and there is no `valgrind` or TCG plugin here for a deterministic
count. Quote code size and instruction count from the artefact, as the port did.

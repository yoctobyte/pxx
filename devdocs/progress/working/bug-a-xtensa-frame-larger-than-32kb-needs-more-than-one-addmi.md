---
slug: bug-a-xtensa-frame-larger-than-32kb-needs-more-than-one-addmi
track: A+S
prio: 55
type: bug
status: working
found: 2026-08-30
found-by: frankS
summary: "`pascal26 --target=xtensa compiler/compiler.pas` fails with `target xtensa (call0): stack frame too large (> 32 KB) for a single ADDMI`. ADDMI shifts an 8-bit immediate by 8, so it reaches +/-32 KB in 256-byte steps; a frame bigger than that needs a second ADDMI or a materialised constant. This is NOT the reach family the parent ticket predicted xtensa would share with riscv32 -- it is frame size, and it was a THIRD distinct defect that ticket had not measured."
owner: frankA
---

# An xtensa frame larger than 32 KB needs more than one ADDMI

## Measured

```
$ compiler/pascal26 --target=xtensa --platform=posix compiler/compiler.pas /tmp/out
pascal26:1437: error: target xtensa (call0): stack frame too large (> 32 KB)
  for a single ADDMI
```

Reached only after `bug-a-no-cross-target-can-build-the-compiler-itself`'s
LoadFile normalisation cleared the blocker in front of it, so this is what
xtensa hits *next*, not instead.

## Why it is its own defect

ADDMI encodes an 8-bit immediate scaled by 256, so one instruction moves the
stack pointer at most ±32 KB and only in 256-byte steps. A frame larger than
that is not a *reach* problem (riscv32's `jal`) and not an ABI problem; it is one
instruction being asked for a range it does not have.

Two candidate fixes, and the choice is worth measuring rather than assuming:
ADDMI followed by ADDI (or a second ADDMI) covers a wider range for two
instructions and no register; materialising the offset with the existing
`EmitLoadConstXtensa` and using ADD covers the full 32 bits but costs a scratch
register in the prologue, where the ABI constrains which are free. The windowed
ABI's ENTRY instruction has its own, tighter frame limit and must be checked
separately — it is not the same encoding.

## What still works, so nobody over-reads this

Ordinary programs cross-build and RUN on hosted xtensa — 97 of the differential
corpus, the signal family, and the exception battery. This is specifically the
compiler's frame sizes.

## Gate

`make compiler/pascal26`, then `pascal26 --target=xtensa --platform=posix
compiler/compiler.pas` must produce an artifact; plus `make test-xtensa`, since
every proc prologue on the target goes through the changed sequence.

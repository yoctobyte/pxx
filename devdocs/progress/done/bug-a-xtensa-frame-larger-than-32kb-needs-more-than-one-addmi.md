---
slug: bug-a-xtensa-frame-larger-than-32kb-needs-more-than-one-addmi
track: A+S
prio: 55
type: bug
status: done
found: 2026-08-30
found-by: frankS
owner: frankS
resolved: PENDING-COMMIT
summary: "FIXED 2026-08-31. The prologue reserves six 3-byte slots and PatchXtensaFrameAdjust writes a CHAIN of ADDMIs into them, NOPping the rest -- six because exactly ONE procedure in the whole compiler exceeds 32 KB and it wants 136448 bytes. The Call0 error was only the visible half: the WINDOWED arm had NO check and EncodeXtensaAddmi masks its immediate, so it silently miscompiled -- measured, the pre-fix compiler ACCEPTS a 40 KB frame under --xtensa-abi=windowed and the binary SEGFAULTS. One helper now serves both ABIs. xtensa still cannot build the compiler: it now reaches the NEXT wall, `j displacement -169568 outside -131072..131071`."
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

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.


## Resolution (frankS, 2026-08-31)

Fixed. The interesting half is the ABI that had no error message.

### The windowed arm was silently miscompiling, and that is the real finding

This was filed off the Call0 diagnostic. The windowed arm has the same 32 KB
ceiling and **no check at all** -- `EncodeXtensaAddmi` masks its immediate with
`(imm div 256) and $FF`, so an oversized frame encoded a different, smaller
adjustment and the prologue handed the body a frame that was not there.

Measured on the pinned pre-fix compiler, same source, both ABIs:

| ABI | pre-fix | post-fix |
| --- | --- | --- |
| Call0 | `error: stack frame too large (> 32 KB)` -- refuses | correct output |
| **windowed** | **compiles, then SEGFAULTS** | correct output |

A loud bound and a silent wrap are the same defect wearing two faces, which is
what happens when one rule is written out twice. There is now ONE helper,
`PatchXtensaFrameAdjust`, for both ABIs.

### Why SIX slots

The prologue reserves `XT_FRAME_SLOT_INSNS` 3-byte slots instead of one and the
patch writes as many ADDMIs as the frame needs (each reaches -32768), NOPping the
rest. Small frames still use a single ADDI.

**Six is measured, not chosen.** A throwaway instrumented build that printed
every oversized frame and clamped it found **exactly one** procedure in the whole
compiler over 32 KB, wanting **136448 bytes** -- five ADDMIs, so the sixth is
headroom. The error names the actual size and the bound.

### `code=` COULD NOT MEASURE THE COST, and it reported PASS-shaped nonsense

The first cost measurement said the change was free: `code=221036B` before and
after, identical file size. It is not free -- it is **+15 bytes per procedure**.

`code=` is **quantised at ~8 KB here**. Swept deliberately: slots = 1, 2 and 6
all report `code=221036`, while the emitted NOP count goes 243 -> 428 -> 1072
(+829 nops, ~166 procs x 5, ~2.5 KB of real instruction stream). Only at
slots = 20 does the number move, and then by exactly 8192.

It was the *positive control* -- forcing the constant to 20 to see whether the
number could move AT ALL -- that caught it, not the reasoning. A measurement that
cannot come out different is not a measurement.

### The wall behind this one, and the ORDER was not what was predicted

xtensa now clears the frame wall and stops at:

```
error: target xtensa: j displacement -169568 is outside the encodable range
       -131072..131071
```

frankA predicted the jump wall would surface behind the forward-CALL wall. On the
real compiler it surfaced behind the **frame** wall, and the displacement is
**backward** (-169568), not forward. frankA's 1 MB generated body masks it the
other way round, so the two orderings are both real and input-dependent. Handed
to [[bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build]];
the riscv32 model is `Rv32JumpSlotBytes` / `EmitRv32JumpToLabel` /
`PatchRv32JumpSlot` (frankA, `1df4ee490`). One caution from this work: xtensa's
slot is **3 bytes, not 4**, so widening one shifts every `Patch24` site and
`XtensaAlignCode4` boundary after it -- and the fixedpoint sees none of that,
because the compiler still builds.

### A collision, reported rather than quietly won

frankA claimed this ticket at `c6863321d` while I was in it: my own claim never
reached origin, so the ranker correctly offered an unclaimed p55. No competing
code was landed and frankA was told immediately. The mechanism is the known one
-- a pull is a snapshot and nothing re-checks between `next` and `claim` -- and
the cheap guard is to push the claim, which I did not.

### Evidence

`test/test_xtensa_frame_over_32k.pas`, wired into `test-xtensa` on **both ABIs**
as a differential against the native build. ~40 KB and ~80 KB frames (chain depth
2 and 3) plus the small-frame ADDI boundary row; the sums touch first, middle and
last of each array so the whole span is load-bearing, and `outer` lives in the
caller so a frame allocated short or upward corrupts something observable.
Positive control asserted in the table above.

Gate: fixedpoint converged; `tools/gate.sh quick` GREEN; both new rows executed
exactly as written.

---
slug: bug-a-xtensa-frame-larger-than-32kb-needs-more-than-one-addmi
track: A+S
prio: 55
type: bug
status: done
found: 2026-08-30
found-by: frankS
owner: frankS
resolved: 0d21318a2  # implementation replaced in a follow-up; see the section at the end
summary: "FIXED 2026-08-31, and the implementation was REPLACED the same night. The frame is now a patched 32-bit LITERAL (EmitXtensaFrameReserve: XtensaEmitLitHeader + l32r a8 + sub sp,sp,a8), the shape arm32 in the same function has always used -- no bound and no rounding. It replaced a chain of ADDMIs in six reserved slots (frankS, 0d21318a2), by that author's own call: the chain was a second mechanism for a rule the function already had, and its 196608 bound was chosen by taste. The Call0 error was only the visible half: the WINDOWED arm had NO check and EncodeXtensaAddmi masks its immediate, so it silently miscompiled -- the pre-fix compiler ACCEPTS a 40 KB windowed frame and the binary SEGFAULTS. Exact frames also retire the 256-byte windowed rounding. xtensa still cannot build the compiler: the NEXT wall is `j displacement -169568 outside -131072..131071`."
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
- 2026-08-31 — resolved, commit 0d21318a2.


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


## The implementation was replaced the same night (frankA, 2026-08-31)

Two sessions fixed this independently within minutes of each other — frankS's
claim never reached origin, so the ranker correctly offered an unclaimed p55 to
frankA. Reported rather than raced; frankS's chain had landed as `0d21318a2` and
frankS called it for the literal form. **Everything above stands as the record of
how the defect was found and measured. Only the lowering changed.**

### What it is now

```pascal
XtensaEmitLitHeader;                 { j over a 4-aligned literal slot }
patchPos := CodeLen;
EmitI32(0);                          { the frame size, patched at end of body }
xtensa_l32r(reg_xtensa_a8, $FFFF);
xtensa_sub(reg_xtensa_sp, reg_xtensa_sp, reg_xtensa_a8);
```

`PatchProcPrologue` then writes a plain number on both ABIs. This is what the
**arm32 arm three lines below has always done** (`ldr r9, [pc]` over a patched
word, then `sub sp,sp,r9`) — which is the whole argument: the chain was a second
mechanism for a rule the function already carried.

### Why, in the order the two authors agreed on

1. **The bound goes away.** Six slots reach 196608. Five ADDMIs is what the
   compiler needs *today*; there is no argument for six over five or eight
   beyond taste, and a limit chosen by taste is one the next large routine meets
   with no explanation of why it sits where it does.
2. **Windowed frames become EXACT**, because a literal has no step. That removes
   the 256-byte rounding and with it the ~11 levels of recursion on a 3584-byte
   ESP-IDF task stack measured in
   [[bug-a-xtensa-windowed-frame-minimum-256-bytes]] — a fix that makes another
   measured defect's cost disappear.
3. **Cheaper per procedure:** +12.1 bytes against the chain's +15.

### Measured

- **Size: +2456 B on `hello`, +1.13%** (.text 218064 → 220520). Read out of an
  `--emit-obj` build with `readelf -S`, because the compiler's `code=` line is
  **page-quantised** and reported this change as costing *nothing*. Both authors
  hit that instrument independently; the row is now in
  `devdocs/dev/debugging-playbook.md`.
- **`test_xtensa_frame_over_32k.pas` gained a `Huge` row: one 260004-byte
  frame**, deliberately past 6 × 32768 = 196608. It is the positive control for
  the bound being gone, and it was verified to DISCRIMINATE rather than assumed
  to: built against the chain implementation it refuses with that
  implementation's own message —

  ```
  error: target xtensa: stack frame of 260096 bytes exceeds the 196608 the
    prologue reserves (raise XT_FRAME_SLOT_INSNS in symtab.inc)
  ```

  and against this one it compiles and prints the x86-64 oracle's answer. Without
  it the file's largest frame is 80 KB, inside every bound anyone proposed.
- Call0, windowed and riscv32 (control, untouched) all match the native oracle
  on the full file.
- Gate: `make compiler/pascal26` converged 1 round (3504e22a9b3a);
  `tools/gate.sh quick` GREEN.

### One process note worth keeping

The discriminating measurement above was obtained by accident, from a mistake
worth naming: an A/B check run as `git stash; make; …; git stash pop` left
**frankS's binary on disk** while the sources were mine again, and the next run
reported a wrong answer (`huge 36`, the previous revision's value) that read
exactly like a miscompile. `stash pop` restores sources, not binaries. The tell
was the error text naming `XT_FRAME_SLOT_INSNS`, a constant that no longer
exists in the tree — the same "grep the tree for the exact error string" check
CLAUDE.md prescribes for a stale seed.

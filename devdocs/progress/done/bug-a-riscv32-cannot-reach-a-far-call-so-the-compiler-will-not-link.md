---
slug: bug-a-riscv32-cannot-reach-a-far-call-so-the-compiler-will-not-link
track: A
prio: 55
type: bug
status: done
found: 2026-08-30
found-by: frankS
summary: "FIXED. It was not a CALL -- the site was tagged and measured: the refusal came from the intra-body LABEL FIXUP in ir_codegen_riscv32.inc, a forward jump inside ParseFactorCore, one procedure spanning 2.20 MB (offsets 4199288..6396484). A second, larger one sat behind it: the program ENTRY jump, asked for 20089124. Both reserved a single 4-byte JAL for a forward reference. Fixed by reserving the wide slot for a forward jump and letting the REACH TEST pick jal+nop or auipc+jalr at patch time; backward jumps keep the bare 4-byte JAL whenever it reaches. `pascal26 --target=riscv32 compiler/compiler.pas` now produces a 20.2 MB rv32 image that runs under qemu and compiles Pascal to both x86-64 and riscv32. Cost: +1.67% rv32 code (hello 245612 -> 249708); other targets byte-identical."
owner: frankA
---

# riscv32 cannot reach a far call, so the compiler will not link

## Measured

```
$ compiler/pascal26 --target=riscv32 compiler/compiler.pas /tmp/out
pascal26:8307: error: target riscv32: jal displacement 2197196 is outside the
  encodable range -1048576..1048574; the code is too large for this branch form
```

2.20 MB against JAL's ±1 MB. Ordinary programs cross-build and run on riscv32
fine; it is specifically the compiler's size that exceeds the form.

## The shape of the fix already exists in-tree

xtensa hit the identical problem and solved it: `EmitXtensaLongCall`
(`symtab.inc`) materialises the target address into a register and does an
indirect call, and `EmitXtensaCallToCode` picks the short or long form by asking
`XtensaCallReaches`. riscv32 needs the same pair — `auipc`+`jalr` is the natural
long form there, and it is a two-instruction sequence with ±2 GB reach.

The reach test must be the thing that chooses, not a heuristic about program
size: a build that is *nearly* over the line must still emit the cheap form for
the calls that fit.

## Sibling

[[bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build]]
is the same family and is about xtensa's remaining forward-reference case. This
one is riscv32 and is about JAL specifically.

## Gate

`make compiler/pascal26`, then `pascal26 --target=riscv32 compiler/compiler.pas`
must produce an artifact; plus the riscv32 cross battery, since every call in it
now goes through whichever form the new chooser picks.

## What it actually was (measured, not reasoned)

Two hypotheses were wrong before the third was measured, and both were wrong in
the same way -- they were about CALLS, because the ticket's title says call.

1. **The signal-install site.** Ruled out with `--no-signals`: still fails.
2. **The runtime-helper calls** (`ExcSetJmpAddr`, `ExcRaiseAddr`,
   `SigInstallAddr`, `ExcLongJmpAddr`, `SigSetHookAddr`). Six sites routed
   through a new reach-choosing `EmitRiscv32CallToCode`; the error came back
   **byte-identical, same displacement 2197196**. That is what retired the
   hypothesis. The routing was kept anyway -- the helpers sit at the front of
   the image and nothing was reach-checking them -- but it fixed nothing here.
3. **The answer**, from tagging every `EncodeRISCVJAL` call site with an id and
   printing it beside `CodeLen` and the current proc:

   ```
   jal displacement 2197196 ... [CodeLen=6397364 site=16
     proc=ParseFactorCore@4199288->6396484 lbl2 nfix2267]
   ```

   Site 16 is the **label fixup loop** -- a body jumping to its own label.
   `ParseFactorCore` occupies 4199288..6396484: **2.20 MB in one procedure**,
   with 2267 forward jumps in it.

   The x86-64 map says this is a narrow wall and a real one: two procedures
   exceed 1 MB (`ParseFactorCore` 1.15 MB, `PyParseFactorCore` 1.24 MB) and the
   third largest is 0.40 MB.

Behind it sat a second, larger one that only appeared once the first was fixed:
the **program entry jump** (`EmitProgramEntryForTarget` / `PatchProgramEntryJump`),
which reserved one JAL to reach the main body past every proc body in the image,
and asked for **20089124**.

## The fix

A forward jump cannot be widened at patch time unless the space was reserved, so:

- **Backward / known target** -- `Riscv32JalReaches` decides: bare 4-byte JAL
  when it reaches, `auipc`+`jalr zero` when it does not.
- **Forward** -- reserve 8 bytes (`jal zero, 0` + `nop`, the JAL opcode kept so
  the fixup loop can still tell a jump slot from a branch slot), and patch it at
  fixup time to `jal`+`nop` or `auipc`+`jalr` by the same reach test. This is the
  trade `EmitCallProc`'s riscv32 arm already makes for every call.
- Every skip branch over a slot now asks `Rv32JumpSlotBytes` for the size
  **before** it encodes its displacement, which is why both halves live in one
  place instead of being open-coded at the five sites.

Five copies of the same if-known-else-record-a-fixup block collapsed into
`EmitRv32JumpToLabel`.

## Evidence

- `pascal26 --target=riscv32 compiler/compiler.pas` -> 20184940 B of code, an
  ELF 32-bit RISC-V executable.
- That image **runs**: under `qemu-riscv32` it compiles `hello` to x86-64 (which
  then runs natively and prints the right thing) and to riscv32 (which runs
  under qemu and prints the right thing). Parsing anything runs
  `ParseFactorCore`, so the widened jumps executed.
- **Both arms of the chooser fire, and the reach test is what chooses** -- slot
  shapes counted straight out of the artifacts rather than inferred:

  | artifact | `jal`+`nop` (short) | `auipc`+`jalr zero,t0` (long) |
  | --- | --- | --- |
  | hello, riscv32 | 1261 | **0** |
  | the compiler, riscv32 (20 MB) | 80348 | **51** |

  A 20 MB image still takes the cheap form for 80348 of 80399 label jumps. A
  size heuristic would have taken all 80348.
- Differential rv32-vs-x86-64, run one file at a time, on the paths whose skip
  distances this change re-encodes: `test_cross_exception`,
  `test_exception_typed`, `test_exception_finally`,
  `test_except_derived_caught_by_base`,
  `test_div_by_zero_raises_on_every_target` -- all MATCH.
- Untouched-target control: `hello` for arm32, aarch64 and i386 is
  byte-identical in size to the pinned compiler's output; x86-64 is the
  self-host fixedpoint. Only riscv32 moved: 245612 -> 249708 B, **+1.67%**,
  which is 1024 forward jumps x 4 bytes.
- Gate: `make compiler/pascal26` converged 1 round (6b9d17ec4961),
  `tools/gate.sh quick` GREEN.

## Regression test

`make test-riscv32` grew one: a GENERATED `bigbody.pas` -- one procedure with a
4000-arm if-chain, 1146732 B of rv32 code, compiled and run against the x86-64
oracle in 0.9 s. The compiler itself is the only other program that crosses the
wall and it is a terrible regression test (the whole self-build has to fail
first). Generated rather than checked in: the source has to be ~260 KB to
produce >1 MB of code.

It carries its own POSITIVE CONTROL -- an assertion that the body really does
exceed 1048576 B -- because a generator, a backend change or an optimisation
could quietly bring it back under the line and the test would go on passing
while covering nothing. Verified to reject both a small `code=` and a missing
one; the missing case is also what makes the `| tee` safe, since a pipeline's
status is tee's and a failed compile would otherwise exit 0.

Pinned refuses that file today (`jal displacement 1106292 ...`); the new
compiler builds it and it prints the oracle's output under qemu.

## What this does NOT close

`asmtext_rv32.inc`'s own forward-reference patch (inline-asm labels) is still a
bare 4-byte JAL. It was left alone deliberately: those labels are inside one
hand-written asm block, and no block in the tree is anywhere near 1 MB. If one
ever is, it fails loudly with the same message and this is the shape to copy.

## Log
- 2026-08-30 — resolved, commit 1df4ee490.

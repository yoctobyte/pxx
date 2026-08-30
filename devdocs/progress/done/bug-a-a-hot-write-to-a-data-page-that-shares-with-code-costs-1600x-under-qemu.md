---
prio: 45
track: A
status: done
owner: frank-optimize-b4
---

# A hot write to a data page that shares with code costs 1600x under qemu

- **Type:** bug (Track A — ELF layout; file-owned by `compiler/elfwriter.inc`)
- **Found:** 2026-08-30 by frank-optimize-b4, chasing a Track T timeout on
  `test-threads#src:test/test_static_string_literals.pas@2`.
- **Not a codegen defect and not an aarch64 defect.** The same binary is fast
  natively and catastrophic under an emulator. It is an emulation artifact of a
  layout choice — but the test tiers run aarch64 under qemu, so it presents as
  a red tier.

## Measured

`test/test_static_string_literals.pas`, whose row 8 writes a static string
literal's refcount in a 200,000-iteration loop:

| binary | static blocks? | refcount word on a code page? | time |
| --- | --- | --- | --- |
| aarch64 -O0, under qemu-aarch64 | no | — | 1.193s |
| aarch64 -O3, under qemu-aarch64 | yes | **yes** | **99.083s** |
| x86-64 -O3, **native** | yes | yes | **0.009s** |
| x86-64 -O3, under qemu-x86_64 | yes | **yes** | **14.661s** |
| x86-64 -O2, under qemu-x86_64 | no (rc on the heap) | — | 0.435s |
| x86-64 -O3 **padded**, under qemu-x86_64 | yes | **no** | **0.118s** |

The last two rows are the controls that make it a mechanism rather than a
correlation. Removing the static blocks removes it; keeping the static blocks
and moving them **off** the shared page removes it too — and that build is the
*fastest* of the three, so the pass is not the problem.

The page arithmetic, read out of the binaries:

```
SLOW  (aarch64 -O3): 'recycled' rc word 0x420ea8 -> page 0x420000
                     highest proc     0x420710 -> page 0x420000   SAME
FAST  (+75 KB code): 'recycled' rc word 0x433418 -> page 0x433000
                     highest proc     0x42bc50 -> page 0x42b000   different
```

## Mechanism

`elfwriter.inc` emits **one PT_LOAD, RWX**, with the data section immediately
after the code. So the boundary page holds both. A qemu-user-style emulator
tracks which guest pages it has translated code from and invalidates those
translations when the guest writes to them — self-modifying-code detection. A
loop that writes a word on that page therefore re-translates the code on it,
every iteration.

Nothing writes to the data section in a hot loop *until* something puts a
mutable word there. `feature-opt-o3-static-string-literals`
([[bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython]]) does
exactly that: a string literal's managed block, refcount included, is built by
the compiler and lives in the data section. That is what armed it. It is not
what is wrong with it.

## Why it was hard to localise, and that part is reusable

Halving the test **exonerated both halves**:

| measured alone | -O0 | -O3 |
| --- | --- | --- |
| the 200,000-iteration loop row | 1.111s | **0.295s** |
| the other seven rows | 0.039s | **0.019s** |
| all eight together | 1.193s | **99.083s** |

Every part is faster at -O3 and the whole is 83x slower, because the thing that
varies is not a row: it is **an address**. Removing rows shrinks the code, which
moves the data, which moves the literal off the shared page. A bisect over rows
is structurally unable to see it, and each half reads as *exonerating* rather
than as inconclusive.

Also worth stating plainly: **the output is correct at every level and on every
target.** A correct-but-catastrophic result is invisible to every instrument
except a clock with a deadline on it, which is why this arrived as a tier
timeout and not as a bug.

## Two fixes, and they are not alternatives to each other

1. **Page-align the data section** (`elfwriter.inc`). One change, fixes it for
   every future write to `.data`, costs up to 4 KiB per binary. This is the
   general answer and the recommended one — the hazard is not specific to
   string literals, it is specific to *any* mutable word sharing a page with
   code, and the next one will be found the same expensive way.
2. **Stop writing to static literal blocks at all** — guard `PXXStrIncRef` /
   `PXXStrDecRef` (and x86-64's five hand-emitted retain/release sites) on a
   saturated-refcount floor, so a static block is never stored to. This is the
   better answer *for the pass*: it also deletes the `inc qword [rax-16]` from
   every literal site on x86-64 and the whole `PXXStrIncRef` CALL on aarch64,
   and it would let the blocks live in genuinely read-only memory later.
   Its failure mode is forgiving — a *missed* guard drifts a 2^30 refcount, a
   performance miss and not a correctness one — but it grows five hand-emitted
   x86-64 sequences, which is the `rel8` span hazard of
   [[bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows]] and must
   be checked for span, not only for semantics.

Not started. Filed rather than fixed because `elfwriter.inc` is held by
`feature-port-rtl-over-libc`, and because option 2 touches the hottest path in
the runtime and deserves its own sitting rather than the tail of another
ticket's session.

## Interim

`test_static_string_literals` now takes its loop count from `{$ifdef CPUX86_64}`
— 200,000 native, 2,000 emulated. This is not a workaround hiding the cliff:
the count was never part of what the row asserts (the static refcount starts at
2^30, so no reachable iteration count could prove the reference is taken), and
**all four arms produce byte-identical output against one expectation**, which
is the proof that the count is not being asserted. The cliff keeps its own
numbers here.

## Resolution (2026-08-30, frank-optimize-b4)

Fixed in the ELF writer: `PadCodeToPageBoundary` pads `Code[]` so the data
section starts on a page of its own. **The padding goes into `Code[]`, never
into `dataBase`** — there is one `PT_LOAD` with `p_offset = 0`, so a virtual
address *is* `LOAD_ADDR` plus a file offset, and aligning `dataBase` on its own
would desynchronise the two and make every data reference read up to 4095 bytes
early. That version would still have passed the self-host fixedpoint, because a
uniformly-wrong compiler reproduces itself perfectly.

Applied in all three writers (`{$ifdef FPC}` and `{$else}` `writeELF`, and
`writeELF32`), guarded off for the ESP bare-boot image, where the target is SoC
SRAM measured in hundreds of KB and nothing is translating from that page.

**Measured, both arms rebuilt at the same HEAD** with only the three call sites
commented out for the *before* arm — not against an older binary, so nothing but
the padding differs. `-O3 test/test_static_string_literals.pas`:

| arm | before `a2701c58b005` | after `f50ff77ecd42` | |
| --- | ---: | ---: | ---: |
| qemu-aarch64 | 91.69s | **0.32s** | 287x |
| qemu-x86_64 | 13.83s | **0.09s** | 154x |
| native x86-64, 200 runs, interleaved | 6.50 / 5.10 ms | 5.85 / 5.30 ms | no measurable change |

All six runs exit 0 and print the same nine lines ending `done`.

**Read the native row as a null, not as a result.** The runs were interleaved
before/after/before/after so the noise floor would be visible: 5.10 ms and
6.50 ms are *both* the before arm. A single pair would have supported a
defensible 9% "regression" or 20% "win" depending on which sample landed where.
The padding costs nothing where there is no emulator, and that is all these
numbers say.

### The bug this fix shipped with for one build, worth more than the fix

The first version wrote the padding as `Code[CodeLen] := 0; Inc(CodeLen)`,
bounds-checked against `MAX_CODE`. **`MAX_CODE` (32 MiB) is the logical bound —
the largest program we accept — and `CodeCapacity` (starting at 64 KiB) is the
physical one.** `Code` is `array of Byte`, grown on demand by `GrowCode`, so
only the second can be overrun, and the check was present, deliberate, and
against the wrong number. The safe path (`EmitB`) was a call away and the unsafe
one was one character shorter.

The symptom was nowhere near the cause. The overrun landed in `GlobFix` and
zeroed all 185 entries, so the writer then ran 185 iterations of
`Patch32(0, bssBase + 0)`: every global reference patched to the same wrong
value at code offset **0**, on top of the entry instruction's opcode, and all
185 real sites left holding zero. `test/test_ansistring.pas` died `SIGILL` on its
first instruction, with a fixup table that had been correct 200 lines earlier.

Two things found it, and neither was reasoning about the byte diff:

- **The incoherence.** "The patch is off by one" and "the patch is missing" each
  fit their own evidence and contradict each other. When two readings are
  locally true and jointly incoherent, neither is right — both are downstream of
  something neither describes. That signal was available two rounds before it
  was used.
- **Two `writeln(StdErr)` lines** around the pad loop: `gf0.pos` **1 before, 0
  after**. One number, and the whole story collapses to it.

And one control that a self-hosting compiler always needs: rebuilding with the
fix changes *two* things — the writer pads, and the compiler binary is itself
padded — so "it works now" cannot say which. Having the known-good unpadded
compiler build a padded-logic compiler, and finding *that* compiler's output
broken too, pinned the fault to the writer and cleared the self-host binary
before anything else was touched.

Follow-on, filed and deliberately not built here:
`feature-a-second-pt-load-so-data-is-not-executable` — the padding removes the
shared *page*, not the shared *segment*, and 4096 is what the measured emulators
use rather than a proof.

## Log
- 2026-08-30 — resolved, commit 75d2ba662.

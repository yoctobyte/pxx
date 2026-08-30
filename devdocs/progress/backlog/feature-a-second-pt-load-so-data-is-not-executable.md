---
prio: 50
track: A
status: backlog
owner: ""
---

# Give data its own PT_LOAD (R+W, no X) instead of one RWX segment

- **Type:** feature (Track A — ELF layout; file-owned by `compiler/elfwriter.inc`)
- **Filed:** 2026-08-30 by frank-optimize-b4, at the coordinator's request, as
  the deliberate follow-on to
  `bug-a-a-hot-write-to-a-data-page-that-shares-with-code-costs-1600x-under-qemu`.
- **Not urgent and not a bug.** Every pxx binary works today. This is the
  structural version of a fix that has already landed in its cheap form.

## What landed instead, and why this ticket exists

The 1600x qemu cliff was fixed by **padding `Code[]` so the data section starts
on its own page** (`PadCodeToPageBoundary`, `elfwriter.inc`). That removes the
*shared page*, which is the whole of the measured hazard, for up to 4 KiB per
binary and about ten lines.

It does not remove the *shared segment*. There is still exactly one `PT_LOAD`,
flags **RWX**, `p_offset = 0`, covering headers, code, data and bss together.
Two consequences survive the padding:

1. **All data is executable and all code is writable.** A stray jump into data
   runs it; a stray store into code is permitted. Neither is exploited by
   anything we ship, and nothing in the test matrix notices — which is exactly
   why it stays quietly true.
2. **The padding is a page-size guess.** `ELF_DATA_PAGE = 4096` is what the
   measured emulators use. A host or emulator configured for 16 KiB pages
   leaves a residual shared page and the cliff comes back, quieter. A real
   segment boundary is enforced by the loader at whatever the page size is,
   so it cannot drift.

## The change

Split into two `PT_LOAD`s: `[headers+code]` R+X, `[data+bss]` R+W. Both keep
`p_offset` = their file offset and `p_vaddr = LOAD_ADDR + p_offset`, so the
identity the whole writer depends on — **a virtual address IS `LOAD_ADDR` plus a
file offset** — is preserved and no fixup arithmetic changes. The page padding
then becomes the mechanism that satisfies the second segment's alignment rather
than a standalone workaround, and its comment should say so.

## Scope — the part that makes this bigger than it looks

`phCount` is not a local decision. It is **2** normally and **4** with externals
(`PT_INTERP` + `PT_DYNAMIC`), and `codeOffset` is `CODE_OFFSET` or
`DYNAMIC_CODE_OFFSET` accordingly — both are *constants chosen to match the
phdr count*, because the code starts immediately after the program headers.
Adding a `PT_LOAD` shifts `codeOffset` by 56 bytes in both configurations, and
those constants are read in more places than the writer:

- `writeELF` ({$ifdef FPC} and {$else} copies — **both**, they are maintained in
  parallel and drift is the standing hazard in this file)
- `writeELF32` (i386 / arm32 / xtensa / riscv32; the ESP bare-boot path must
  keep its current single segment — see the `EspBareBoot` guard on the padding)
- `--proc-map` in `compiler.pas`, which hardcodes `LOAD_ADDR + CODE_OFFSET`
- the DWARF section writer, which is handed `codeOffset` and `entry`
- `WriteMapFile`

**Do not do this one incrementally under a flag.** A half-applied phdr layout
produces a binary that loads and runs and is wrong in the addresses it reports,
which is the failure mode this repo is worst at noticing.

## Gate

`make compiler/pascal26` (the self-host fixedpoint), plus:

- `readelf -l` shows two `PT_LOAD`s with the expected flags on x86-64 and
  aarch64, and the ESP bare-boot image still shows one;
- the qemu subjects from the parent ticket stay at their post-padding times;
- a cross build for each 32-bit target still runs under `tools/run_target.sh`;
- `-g` output still resolves (`shoff` and the section table follow `filesz`).

## Explicitly NOT in scope

Relocating `bss` away from `data`, `PT_GNU_RELRO`, and anything that would make
`p_vaddr` differ from `LOAD_ADDR + p_offset`. That identity is load-bearing
across the whole writer and is worth more than the segment split.

## Re-priced 30 → 50 by the coordinator, 2026-08-30

**The reason it sat at 30 was that touching this layout was frightening, and it
is measurably less frightening than it was four hours ago.**

`df98fea47` landed `AlignCodeForData` plus `CheckDataBaseAligned` as an `Error`
at each `dataBase :=` site. Before that commit, the data section had **never**
been aligned on any target — it began wherever code happened to end — and 41
xtensa windowed programs were green only because `75d2ba662`'s 4096-byte page
pad word-aligned it as a side effect. A second `PT_LOAD` moves exactly that
boundary, so this ticket's real cost was never the code: it was that landing it
could have silently taken 41 programs back to SIGBUS with no diagnostic, and
nothing in the repo would have noticed.

Two things changed that, both on 2026-08-30:

- **The invariant is explicit and asserted.** This change can no longer take the
  41 back silently — it either trips `CheckDataBaseAligned` or it passes.
  b4's own words, and it is the strongest argument for the re-price.
- **There is now an executed canary.** `test_cross_record` windowed runs in
  `test-xtensa` with two outcome slots (exit code and output as separate rows),
  and it is a *measured* canary: it SIGBUSes at `75d2ba662^` and passes after.
  Before today, `test-xtensa` executed 107 rows, all Call0, and its two windowed
  rows were compile-only behind a comment claiming there was no runner — which
  was false, and had been for as long as the hosted profile existed.

**An invariant that converts a silent regression into a loud one is what makes a
previously-scary change routine.** That is the whole re-price: the work did not
get more valuable, the risk got legible. Cash it in while the lane that built the
invariant still holds the context.

Not a claim on anyone; ranked, not assigned.

---
prio: 40
track: T
type: chore
status: new
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: "tools/esp_run_bare.sh defaults to `--chip esp32c3`, which is riscv32, so the routine ESP path exercises ONE of the two ESP targets and xtensa NilPy has no regular coverage at all. This is a COVERAGE gap and explicitly NOT a break: NilPy builds for xtensa fine with `--xtensa-abi=windowed --xtensa-long-calls --emit-obj` (empty .npy 975,588 B, `print(1)` 975,740 B, measured 6fb91c73e88e and matching frankb-8e byte for byte). The cost of the gap is measured rather than hypothetical: on 2026-09-22 TWO seats independently concluded that NilPy could not target xtensa AT ALL and one filed it at p70, because both reproduced a default-ABI flag mistake and neither had a working xtensa NilPy row anywhere to contradict them -- the whole episode is written up in rejected/bug-a-nilpy-cannot-target-xtensa-at-all-an-empty-npy-file-refuses. A green row is not only a regression detector; it is the thing that stops a reader inventing a broken target. NOTE THE ASYMMETRY IS SHARPER THAN `one chip untested`: xtensa is the PRIMARY ESP target per the S-lane rule (riscv32 merely also works), so the untested one is the one that matters more. NOT PROPOSING A DEFAULT CHANGE -- flipping the default to esp32s3 would move the blind spot rather than close it, and c3 is the cheaper chip to run. The ask is one xtensa NilPy row somewhere that runs regularly, with the windowed/long-calls/emit-obj flags recorded in it so the next reader finds the working command instead of re-deriving it."
---

# The bare ESP runner exercises riscv32 only

`tools/esp_run_bare.sh` takes `--chip esp32c3|esp32s3` and defaults to
**esp32c3**, i.e. riscv32. The Makefile's bare ESP suite invokes it 34 times and
the xtensa rows are a minority; for **NilPy specifically** there is no routine
xtensa row at all.

## This is a coverage gap, not a break

NilPy builds for xtensa:

    --target=xtensa --xtensa-abi=windowed --xtensa-long-calls --platform=esp --emit-obj
      empty .npy   975,588 B
      print(1)     975,740 B

Measured at `6fb91c73e88e`, matching an independent run by frankb-8e byte for
byte. The default Call0 ABI is what overflows the `addi` range; windowed plus
long-calls clears it, and `--emit-obj` is the IDF profile's documented output
form (it emits an object for the IDF link rather than a complete executable).

## What the gap actually cost, measured

On 2026-09-22 **two seats independently concluded that NilPy could not target
xtensa at all**, and one of them (me) filed it at **p70** with an empty-file
floor case and a scope table. Both of us had reproduced a **flag mistake** —
every row in that table used the default ABI — and neither of us had a working
xtensa NilPy row anywhere in the tree to contradict us. The full write-up is in
`rejected/bug-a-nilpy-cannot-target-xtensa-at-all-an-empty-npy-file-refuses`.

**That is the argument for this ticket and it is not the usual one.** A green row
is normally justified as a regression detector. Here it would have cost two
seats roughly an hour between them by being *present*, before any regression
existed: **an existing green row is what stops a reader inventing a broken
target.** A missing row does not merely fail to catch a defect; it leaves a hole
that a confident wrong diagnosis expands into.

## The asymmetry is sharper than "one chip untested"

**xtensa is the PRIMARY ESP target** — the S-lane rule says so, with riscv32
merely also working. So the untested one is the one that matters more, and the
default sends every casual run to the other.

## Not proposing a default change

Flipping the default to `esp32s3` would move the blind spot rather than close
it, and c3 is the cheaper chip to run. The ask is **one xtensa NilPy row that
runs regularly**, with the working flag set recorded in the row itself so the
next reader finds the command instead of re-deriving it — which is the specific
thing neither seat could do yesterday.

## Scoped deliberately small

`prio: 40`. Nothing is broken, nobody is blocked, and the whole content is one
row plus the flags written down beside it. It is filed at all because the
episode it prevents has already happened once and was expensive in attention
rather than in tokens.

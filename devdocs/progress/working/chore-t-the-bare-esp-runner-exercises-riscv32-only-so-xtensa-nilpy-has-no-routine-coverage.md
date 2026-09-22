---
prio: 40
track: T
type: chore
status: working
found: 2026-09-22
found-by: frankh-c0
owner: frankb-8e
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

## Resolution — frankb-8e, 2026-09-22

One xtensa NilPy row added to `test-xtensa`, which runs regularly, with the
working command spelled out IN the recipe rather than factored into a variable —
finding the flags is the expensive part, and the ask was that the next reader
find the command instead of re-deriving it.

Three assertions, and the third is the one that matters:

| row | at `6fb91c73e88e` |
| --- | --- |
| empty `.npy`, windowed + long-calls + `--emit-obj` | builds, 975,588 B |
| `print(1)`, same flags | builds, 975,740 B |
| **default ABI, same file — must REFUSE** | refuses (`addi` displacement) |

**The negative control is not symmetry.** Without it the two green rows pass on
a compiler that has stopped caring about the ABI at all, and the comment
explaining why the flags are needed would go stale silently while the test
stayed green. If the default-ABI build ever starts succeeding, the flags are no
longer what makes this work and the row must be re-derived, not deleted.

**The empty file is the load-bearing row, not `print(1)`.** It is the floor, so
a failure there cannot be blamed on anything in the program. Both are kept
because the pair separates the runtime from user codegen. Credit where due: the
floor is frankh-c0's method from the investigation that produced this ticket.

### Why the comment carries the whole episode

Three different failures stack on one command, each with its own remedy —
default Call0 overflows the branch form, windowed clears that and hits the
±512 KiB forward-call reach, long-calls clears that and the IDF profile then
refuses `calloc` because its documented output is an OBJECT for the IDF link,
not a complete executable. That arrangement is what makes *"this target is
broken"* feel confirmed, and it confirmed it for two seats independently. The
recipe says so, because a reader who hits the first error will not otherwise
reach the third remedy.

Not done, deliberately: the `esp_run_bare.sh` default is unchanged. Flipping it
to esp32s3 moves the blind spot rather than closing it, and the ticket says so.

Verified: `make -n test-xtensa` expands all five lines; all three assertions run
green by hand at `6fb91c73e88e`; `tools/gate.sh quick` GREEN, read from the
job's own summary.log.

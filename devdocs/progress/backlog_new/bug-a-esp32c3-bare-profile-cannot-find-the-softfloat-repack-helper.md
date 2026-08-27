---
slug: bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-repack-helper
track: A
prio: 45
type: bug
blocked-by: []
summary: "`--target=esp32c3 --esp-profile=bare` refuses any program with a float in it: `compiler error: softfloat repack helper not found (uses softfloat?)`. The same source builds on `--target=xtensa --esp-profile=bare` and on plain `--target=esp32c3`, so it is the esp32c3+bare combination specifically. Pre-existing on pinned."
status: backlog
---

# `--esp-profile=bare` on esp32c3 cannot find the softfloat repack helper

## Repro

```pascal
program rw;
var a: array[0..999] of Real;
begin a[0] := 1.0; end.
```

```
$ ./compiler/pascal26 --target=esp32c3 --esp-profile=bare rw.pas /tmp/o
pascal26:3: error: compiler error: softfloat repack helper not found (uses softfloat?)
  near:       >>> end  unit
```

The matrix — one cell fails, and it is not the cell you would guess:

| invocation | result |
| --- | --- |
| `--target=esp32c3` (no profile) | builds, `Real` = 4 bytes |
| `--target=riscv32 --esp-profile=bare` | builds |
| `--target=xtensa --esp-profile=bare` | builds |
| **`--target=esp32c3 --esp-profile=bare`** | **the error above** |

`--target=esp32c3` and `--target=riscv32` are required to produce byte-identical
output — the Makefile asserts it with `cmp` — and they do, *without* the profile
flag. Adding `--esp-profile=bare` breaks the esp32c3 spelling only. That is the
interesting part: two spellings of the same target diverge in the presence of a
flag that ought to be orthogonal to which spelling was used, which smells like
the SoC name reaching a decision that should only see the arch.

## Not a regression

Verified against `stable_linux_amd64/default/pinned`: identical error, identical
wording. This predates the current work and is filed on its own merits, not as
fallout.

## Why it matters

`--esp-profile=bare` is the documented way to build for a bare ESP32-C3
(`docs/targets/esp32.md`, "Mode 1"), and esp32c3 is the natural spelling to
reach for when that is the chip. Anyone following the docs with the obvious
target name hits this on their first program containing a float, with a
diagnostic that says `compiler error:` — i.e. it presents as an internal
compiler fault, not as something the user did.

The message's own hint ("uses softfloat?") is also misleading here: adding
`uses softfloat` is what the docs prescribe, and this fires regardless.

## Filed, not fixed

Found while measuring `Real` width per target for
[[bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets]]. Filed
rather than chased because it is a separate mechanism from that fix and had no
business riding along on it.

## Gate

`--target=esp32c3 --esp-profile=bare` builds the repro above and stays
byte-identical to `--target=riscv32 --esp-profile=bare`. A test-core row for the
combination, since the existing esp coverage evidently does not have one — that
is the second half of this bug.

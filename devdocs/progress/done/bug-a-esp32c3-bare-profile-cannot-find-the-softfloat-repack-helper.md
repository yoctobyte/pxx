---
slug: bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-repack-helper
track: A
prio: 45
type: bug
blocked-by: []
summary: "`--target=esp32c3 --esp-profile=bare` refuses any program with a float in it: `compiler error: softfloat repack helper not found (uses softfloat?)`. The same source builds on `--target=xtensa --esp-profile=bare` and on plain `--target=esp32c3`, so it is the esp32c3+bare combination specifically. Pre-existing on pinned."
status: done
owner: claude-A-S
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


---

## Resolution (2026-08-27)

**The filed diagnosis was wrong in both directions, and the matrix had already
moved before the fix.** Re-measured on HEAD first:

| invocation | filed | measured today |
| --- | --- | --- |
| `--target=esp32c3 --esp-profile=bare` | fails | fails |
| `--target=riscv32 --esp-profile=bare` | **builds** | **fails, identically** |
| `--target=xtensa --esp-profile=bare` | builds | builds *this* repro, fails on `a[1] := a[0] * 2.5` |
| `--target=esp32c3` (no profile) | builds | builds |

So it is neither esp32c3-specific nor riscv-specific, and the SoC-name theory in
the ticket ("the SoC name reaching a decision that should only see the arch") is
not what is happening — the two spellings agree, and always did. xtensa looked
clean only because the filed repro is one operation short of the wall: a `Real`
constant store folds, an `Integer -> Real` conversion does not.

### Root cause

`pasparser_prog.inc` pulled the `softfloat` unit ambiently for hosted riscv32
and arm32 and **skipped the ESP-class targets entirely** — the exact set that
has no FPU at all and therefore lowers *every* float op to a `__pxx_*` kernel
from that unit. The failure surfaced far from the cause, at codegen, as
`compiler error: ...` — an internal-fault-shaped diagnostic for an ordinary
program built the way `docs/targets/esp32.md` prescribes.

`cparser.inc` carried its own copy of the same guard with the same hole
(`grep for the sibling`): a bare C translation unit with a `double` in it died
the same way.

### Fix

- **Both frontends now pull `softfloat` on demand for ESP-class targets**, from
  a token scan, matching the `math` / `textfile` pulls already in the same
  function. On demand and not unconditionally because softfloat is ~64KB of code
  on riscv32 / ~54KB on xtensa, which is real flash, and the typical MCU program
  has no float. Measured: a float-free bare image is **byte-for-byte the size it
  was** (51512B on riscv32, 44388B on xtensa, 724B for C).
- The signal sets differ per language and that is deliberate: Pascal's `/` is
  always real division and is a float tell; C's is integer division on integer
  operands and is not. Pascal keys on `tkFloat` / the four float type keywords /
  `tkSlash`; C on `tkFloat` / `tkCFloat` / `tkCDouble`.
- **The 12 codegen diagnostics were collapsed into one wording**
  (`SoftFloatMissing`, `util.inc`) that stops claiming a compiler fault and says
  what to do: *"this target has no FPU and the soft-float kernel X is not
  linked; add `uses softfloat` to the program"*. That is the escape hatch for the
  scan's remaining blind spot — a float reaching codegen through a name the token
  scan cannot see, e.g. `var x: TFloatAliasFromSomeUnit`.

### Coverage — the second half of the bug, as the gate asked

`test/test_esp_bare_float.pas` (+ `.c`) and rows in **test-core**:
all four bare spellings build; each SoC name stays byte-identical to the generic
arch it defaults from; the x86-64 oracle pins the values (`7|16|32|75|ESP BARE
FLOAT OK`); and a float-free bare image is asserted **smaller** than the float
one, so the day the scan silently becomes unconditional, that row goes red.
`test-esp-bare` gained an execution row per chip, skipped-with-a-reason where the
Espressif qemu fork is absent (it is absent on plexus — build-and-compare is what
can be proved here, and it is what the gate asked for).

### Filed, not chased

[[bug-a-xtensa-cannot-lower-an-int64-to-float-conversion]] — the test's original
`Int64 -> Double` arm is refused outright on xtensa. Removed from the test rather
than routed around with a target ifdef; the ticket says how to restore it.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.

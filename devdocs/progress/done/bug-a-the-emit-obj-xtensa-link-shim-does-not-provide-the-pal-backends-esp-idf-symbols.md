---
track: A
prio: 45
type: bug
status: done
owner: ""
created: 2026-09-06
found-by: frankA
tags: [emit-obj, xtensa, esp, testing]
blocked-by: []
summary: "RESOLVED, and IT IS THE HARNESS HALF OF frankZ's [[bug-a-emit-obj-retains-pxxassert-so-one-ansistring-in-it-imports-the-whole-esp-pal]] (prio 65, filed 2026-09-05, bisected to f0a1a8be9) -- I re-diagnosed an already-filed bug and their diagnosis is the better one, reaching the cause where mine stopped at the shim. What was genuinely missing and is fixed here: the link step named its stubs BY HAND, so it doubled as an unplanned alarm for whatever the RTL imports, and the two xtensa links were separated by `;` so the first failure was swallowed and only the windowed line ever reached a log -- which is why this read as a windowed-ABI problem. tools/emit_obj_stub_shim.sh now generates the shim from each object's own UND list; asserted on `und seen` and NOT on stubs generated, because riscv32 legitimately needs zero; the shim linked ALONE must fail, so the step cannot stop being able to fail. test-emit-obj is GREEN. THE DEFECT UNDERNEATH IS UNCHANGED AND THIS ROW NO LONGER GATES IT: the xtensa object still imports 18 lwip_* plus vTaskDelay and esp_timer_get_time for a routine the program never calls, so the recipe now PRINTS that count and names frankZ's ticket rather than failing on it. Whether it should gate is a live question for the full-green ledger, raised with frankuser and frankZ rather than decided here."
---

# The emit-obj xtensa link shim does not provide the PAL backend's ESP-IDF symbols

Found 2026-09-06 while closing
[[bug-a-the-i386-pic-prefix-guard-reads-a-displacement-byte-as-a-prefix]] — a
textbook case of the loud defect hiding the quiet one. The i386 relocation
assertion aborted `test-emit-obj` roughly 700 recipe lines before this, so this
step had not been reached in however long the i386 row had been red.

## Measured

    XT=…/xtensa-esp32s3-elf-gcc
    $XT -nostartfiles -Wl,-e,main <shim>.c <obj> -o /dev/null

| object built by | ABI | undefined references |
| --- | --- | --- |
| `stable_linux_amd64/default/pinned` | windowed | **25** |
| HEAD (`189e9b74036e`) | windowed | **25** |
| HEAD | default | **25** |
| HEAD, riscv32 | — | **0** |

Names: `lwip_getsockname`, `lwip_getpeername`, `lwip_getsockopt`, `lwip_ioctl`,
`lwip_accept`, `esp_timer_get_time`, `vTaskDelay` and the rest of the PAL
socket/timer surface, in `PalBackend*` functions.

**The pin and HEAD agreeing at 25 is what makes this not a regression**, and the
two ABIs agreeing is what makes it not about the windowed ABI. Only the windowed
line appears in a log because the recipe runs it last and the earlier failure's
`&&` swallows its echo.

## Why the recipe's own comment now points the wrong way

The recipe carries a paragraph from `regression-test-emit-obj-test-emit-obj`
saying the shim's gap *"read as riscv32-specific and is not: all three objects
carry `UND ext_aliased_link` identically … Only the riscv32 line appeared in the
log because make ABORTS there and never reaches the xtensa links."* That was
right about `ext_aliased_link`, which the shim now defines. The remaining gap is
a different set of symbols and it **is** target-specific — riscv32 links clean
because its PAL backend does not import lwip or FreeRTOS. Reading that paragraph
today tells you the opposite of what is true.

## What the step is actually for

It asserts an emitted `.o` is LINKABLE — the assertions above it check
`REL (Relocatable file)`, `Xtensa`, a `GLOBAL` `app_main` and `R_XTENSA_32`.
Nothing here wants a working ESP-IDF, and pulling one in would make a CI-visible
row depend on an SDK checkout.

So: extend the shim with empty stubs for what the PAL backend imports, the way
`ext_notify`/`ext_aliased_link` are already stubbed. **Generate the stub list
from the object's own UND symbols rather than typing today's 25** — a hand-typed
list is a hand-counted constant over an emitter that can grow, and the next PAL
addition re-reds the row with an unrelated-looking diff. `readelf -sW` filtered
to `UND` gives the list; anything the shim already defines is skipped.

The alternative — dropping the link and keeping only the readelf assertions —
loses the one check that the relocations are consumable, and is a narrowing.
Prefer the stubs.

## Repro

    make test-emit-obj    # PXX_ALLOW_FULL_SUITE=1; fails at the xtensa link,
                          # after every i386 row now passes

## RESOLVED — the shim is generated from the object's own UND list

`test-emit-obj` is GREEN. `tools/emit_obj_stub_shim.sh <obj>...` reads each
object's undefined symbols and emits `void f(void) {}` for every one the shim
does not own, so the next PAL addition cannot re-red this row with a diff that
looks unrelated to the PAL.

`ext_notify`, `ext_aliased_link`, `main` and `app_main` are excluded by name.
`ext_aliased_link` matters most: the readelf assertions above demand the object
leave it UND, so letting the generator answer for it would make the script the
reason the row passes rather than the compiler.

### The counts, and why riscv32's zero is not a failure

| object | UND seen | stubs generated |
| --- | --- | --- |
| `test_emit_obj_rv.o` | 2 | **0** |
| `test_emit_obj_xt.o` + `_xt_windowed.o` | 35 | **33** |

riscv32 imports only the two names the shim owns; xtensa's PAL backend brings
`lwip_*`, `esp_timer_get_time`, `vTaskDelay` and the libc surface. **So a zero
stub count is a real answer and the guard cannot be built on it** — the first
version of this asserted `stubs generated >= 1` and failed riscv32 immediately,
which is the flag-whose-default-is-a-real-answer shape. The assertion is on
`und seen`, where 0 genuinely does mean the object was never read.

### What the step can still fail on, since generating the stubs narrows it

It can no longer fail on a missing IMPORT. It still fails on the relocations,
which is what it was written for. Two guards keep that honest and both were
measured, not assumed:

- **the stub shim linked ALONE must fail** (no object, so `app_main` is
  undefined) — verified rc=1. Without this, a link step that had stopped being
  able to fail would certify every object after it.
- **`und seen` non-zero**, so a generator that read nothing is caught rather
  than reproducing the original failure and looking like a pass.

`-fno-builtin`, because the stubs redefine names gcc knows as builtins
(`calloc`, `fwrite`, …) with a `void f(void)` signature. Without it the link
succeeds while printing conflicting-type notes, and an instrument that warns and
passes anyway is one whose next real message nobody reads.

### One defect fixed in passing

The two xtensa links were separated by `;`, so the first one's failure was
swallowed and only the last command's rc reached make. That is why only the
windowed line ever appeared in a log, and it is what made this read as a
windowed-ABI problem. Both links now `|| exit 1`.

Verified: `PXX_ALLOW_FULL_SUITE=1 make test-emit-obj` rc=0 — needed because
the row under repair is the target itself and quick does not run it.
`tools/gate.sh quick` GREEN.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

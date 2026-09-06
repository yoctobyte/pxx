---
track: A
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankA
tags: [emit-obj, xtensa, esp, testing]
blocked-by: []
summary: "`test-emit-obj` links `test_emit_obj_xt.o` and `test_emit_obj_xt_windowed.o` against a five-line C shim with `-nostartfiles` and no ESP-IDF, but test/test_emit_obj.pas now reaches the PAL socket/timer backend, so the link wants `lwip_*`, `esp_timer_get_time` and `vTaskDelay` and fails with 25 undefined references. NOT A CODEGEN BUG AND NOT NEW: the PINNED compiler gives the same 25 on the same shim, and BOTH xtensa ABIs fail identically -- windowed is not special, it was just the last one in the recipe. riscv32 links clean, so the recipe's own comment that the failure `read as riscv32-specific and is not` has inverted: today it is xtensa-specific. It was invisible until 2026-09-06 because the i386 relocation assertion 700 lines earlier aborted the target first. Either the shim gains stubs for what the PAL backend imports (matching how the riscv32 side is already satisfied) or the xtensa link stops using a bare shim; the link is a LINKABILITY check, so stubs are enough and no ESP-IDF is wanted."
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

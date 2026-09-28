---
track: A
prio: 15
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, the other half of bug-a-wasm32-never-runs-a-units-initialization-section)
tags: [wasm32, units, finalization, atexit, nilpy]
summary: "On wasm32, no unit's finalization ran at normal program end. Nil Python's atexit handlers are carried by a unit's finalization, so none of them ran either. Both drivers end the program by calling PXXExitProcess or the finalizer runner through EmitCallProc, which wasm32 drops. They now record the runner, and WasmEmitMainWrapper calls it after the body's last chunk. Halt already ran the finalizers on wasm32 and still does, once."
owner: ""
---

# wasm32 never runs a unit's finalization or an atexit handler

```python
import atexit
atexit.register(lambda: print("bye"))   # CPython / x86-64: body, bye
print("body")                           # wasm32: body
```

A Pascal unit's `finalization` section was skipped the same way.

## Cause and fix

At the end of the body, `pasparser_prog.inc` calls `PXXExitProcess` if it
exists, and the finalizer runner otherwise. `pyparser.inc` calls the runner
directly. Both calls go through `EmitCallProc` (machine code), and a wasm32
`main` is built from the body's chunks, so neither call existed there. Each
driver now sets `WasmFiniRunner := GetFiniRunnerProc` on wasm32, and
`WasmEmitMainWrapper` calls it after the last chunk. The runner guards itself
with `__pxx_fini_done`, so a `Halt` (which already reached the runner on
wasm32) followed by the fall-off cannot run the finalizers twice.

## Measured (2026-09-29, fixedpoint 1b5cb8f8976e)

- `test/test_a_unit_finalization_runs_on_wasm32.pas` uses two units, where
  `uwasmfini2` uses `uwasmfini` and so must be finalised first. It matches on
  x86-64, i386, arm32, aarch64, riscv32, xtensa windowed/call0 and wasm32.
  With the previous compiler, only wasm32 differs.
  - The expectation is PXX's x86-64 output, not FPC's. FPC 3.2.2 runs these
    finalizers (a file written from one is created), but loses a finalizer's
    console output on stdout and stderr alike.
- `test/test_nilpy_atexit_runs_on_wasm32.npy` covers two handlers (last
  registered runs first), one of which reads state the other changed. It
  equals CPython on x86-64, i386, riscv32 and wasm32. With the previous
  compiler, only wasm32 differs.
- `Halt(3)` on wasm32 exits 3 and runs each finalizer once.
- The 79 wasm32 Makefile blocks: no block changes status.

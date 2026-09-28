---
track: N
prio: 10
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, checking the Nil Python driver after bug-a-wasm32-never-runs-a-units-initialization-section)
tags: [nilpy, wasm32, import, initialization, silently-wrong]
summary: "Under a Nil Python main on wasm32, an imported module's top-level code never ran, so every module-level name read as zero (`modx.X` printed 0 where CPython prints 42). The same was true of any Pascal unit's initialization. The Nil Python driver calls the init procs through EmitCallProc, which wasm32 drops, just as the Pascal driver did. It now records the chunk the calls belong before, the same way the Pascal driver does."
owner: ""
---

# wasm32 never runs an imported module's top-level code

```python
# modx.py
X = 40 + 2
# main
import modx
print(modx.X)        # x86-64 / CPython: 42    wasm32: 0
```

## Cause and fix

This is the same defect as
bug-a-wasm32-never-runs-a-units-initialization-section.md, at the Nil Python
driver's call site. An imported module compiles into an `__init_<module>` proc
registered in InitProcs. `pyparser.inc` calls those procs through
`EmitCallProc` after `CompilePendingGlobalInits`, and on wasm32 that emits
nothing that runs. The driver now sets `WasmUnitInitAt :=
WasmMainChunkCount` at that point, and `WasmEmitMainWrapper` makes the calls
there.

## Measured (2026-09-29, fixedpoint 1e75507f1263)

- `test/test_nilpy_an_imported_modules_top_level_runs_on_wasm32.npy`, with
  its module `test/wasminit_mod.py`, covers a computed value, a list, a dict,
  a class instance built at module level, and a function that mutates module
  state. It equals CPython on x86-64, i386, riscv32 and wasm32. With the
  previous compiler, only wasm32 differs.
- The 79 wasm32 Makefile blocks: no block changes status against the Pascal-only
  fix.

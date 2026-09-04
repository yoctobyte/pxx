---
slug: bug-a-wasm32-emitted-a-negative-local-index-and-the-module-was-written-anyway
track: A
prio: 55
type: bug
status: done
blocked-by: []
owner: frankA
created: 2026-09-04
found-by: frankb-78 (a .npy module that compiled and would not load)
summary: "wasm32 kept four per-body managed-string scratch locals, allocated on demand; `msval` was allocated by the managed-STORE path only, and WasmVariantPayload reaches the same materialiser without one. A body that boxes a string into a Variant and never assigns one emitted `local.set -1`. A negative index is not an error in an LEB128 writer -- `x shr 7` on -1 walks ten continuation bytes -- so the module was WRITTEN, the compile printed `ok:` and exited 0, and the coverage report recorded no gap. Fixed by routing all four locals through allocate-on-use accessors, which also deletes nine duplicated allocation lines at three sites; WasmBodyU32 now refuses a negative index outright and names the body."
---

# wasm32 emitted a negative local index and the module was written anyway

## The class, which is the reason this is worth more than its own fix

The compile SUCCEEDS. `ok:` is printed, rc is 0, no refusal is recorded, and the
module is invalid. **Every check that stops at "did it build" passes**, and the
wasm32 gap census — which counts coverage-report lines — is structurally unable
to see it, because there is no report line to count. Only a loader or a
validator says anything, and neither was in any recipe.

## Measured

```
printf 'print("hi")\n' > m1.npy
./compiler/pascal26 --target=wasm32 m1.npy m1.wasm     # rc=0, prints ok:
wasm-validate m1.wasm   # rc=1  004593c: error: unable to read u32 leb128:
                        #                 local.set local index
```

`WasmStrLocZ` (`msval`) is declared at `ir_codegen_wasm32.inc:109`, reset to -1
at each body's start, and was allocated at exactly ONE site — the first line of
`WasmEmitManagedStore`. It is READ in both the frozen and the tyAnsiString arms
of `WasmEmitOwnedStr`, which has TWO callers: that store, and
`WasmVariantPayload`.

**Proven with a targeted control, not by reading.** The compiler was rebuilt with
the allocation removed from the accessor and restored at the head of
`WasmEmitManagedStore` — i.e. exactly the pre-fix siting — and the failure came
back at the same body the pre-fix compiler failed at, `pyord_s`
(`compiler/builtin/pylib.pas:3063`). With the allocation in the accessor, the
module validates and `m1.npy` runs and prints `hi` under wasmtime.

`WasmStrLocN/S/O` were correct, and correct by three duplicated copies of the
same `if < 0 then` triple (LoadFile, WasmEmitDynStore, WasmEmitManagedStore) —
the shape that let the fourth drift. Four accessors now, no copies.

## Why no existing row caught it, measured not argued

The pre-fix compiler was rebuilt and all four existing wasm32 variant rows —
`test_cross_variant`, `_single`, `_payload_widths`,
`test_variant_self_assign_is_a_no_op` — emit a VALID module on it. They box
string LITERALS, and a literal is materialised through the string POOL, not
through `msval`. Reaching `msval` needs a string VARIABLE, in a body whose box
is not preceded by a store. **The canonical case was immune by coincidence.**

## Landed

- `WasmScratchMsNew/MsSlot/MsOld/MsVal` — allocate on use, nine duplicated
  allocation lines deleted at three sites.
- `wasmenc.inc`: `WasmBodyU32` refuses `v < 0` and names the body
  (`WasmEncBodyName`, set by the wasm32 codegen at each body start) plus a
  24-line tail of the text form. A guard, not a comment: it was the instrument
  that located this one.
- `test/test_cross_variant_boxed_string_no_store.pas`, wired on all six cross
  targets. It FAILS on the pre-fix compiler (`0x1d1cb`, wasmtime refuses
  function 238) and passes on all six now.

## The residual, and it has no owner yet

Nothing in any recipe validates or loads an emitted wasm module except the rows
that RUN one. A gap of this class in a body no row reaches is still invisible.
`wasm-validate` over every `.wasm` a recipe writes is a different instrument
from running one — cheap, and not filed here because it is Track T's aperture
question, not this bug.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

---
slug: bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps
track: A
prio: 30
type: bug
status: open
blocked-by: []
owner: unassigned
created: 2026-09-01
found-by: frankC (while fixing bug-a-managed-locals-leak-at-ORDINARY-scope-exit-on-wasm32-and-a-variant-local-traps)
summary: "ANY Variant assignment traps on wasm32: `v := 42` in a bare program body, with no procedure in it, gives `wasm trap: wasm unreachable instruction executed`, exit 134. NOT a leak and NOT a scope-exit problem -- the compiler says so itself, in its own broken-body report: `main$0 - statement IR op 43`, which is IR_VAR_STORE. The whole Variant family is absent from this backend: grep counts IR_VAR_STORE 0, IR_VAR_BINOP 0, IR_VAR_BOX 0 in ir_codegen_wasm32.inc against 2, 2, 2 in ir_codegen_riscv32.inc. So this is not a bug in Variant handling, it is Variant not being lowered at all, and the trap is the backend's deliberate unsupported marker (WasmUnsupported -> WasmBodyUnreachable) doing exactly what it is for. Consequence beyond the trap: wasm32's scope-exit release now HAS a PXXVarClear arm (74e33af46) and nothing can reach it, so that arm is written and unverified until this lands -- do not read its presence as coverage. Scope is three IR ops ported from the riscv32 or aarch64 arm, plus whatever Variant RTL the wasi profile is missing; the descriptor-cell indirection this backend uses for record RTTI (WasmRecDescAddr) is the pattern for any blob address a Variant op needs, because wasm32 has no code->data fixups."
---

# wasm32 has no Variant IR arms, so any Variant assignment traps

## Measured

```
program v1;
var v: Variant;
begin
  WriteLn('before');
  v := 42;
  WriteLn('after int assign');
end.
```

`--target=wasm32 -Fulib/rtl/platform/wasi`, `wasmtime run` (48.0.1): exit 134,
`wasm trap: wasm 'unreachable' instruction executed`, and **`before` never
prints** — the whole body is replaced, not just the assignment.

Two controls, both run:

- the same program with the `v := 42` line removed prints `before` and exits 0,
  so declaring a Variant is fine and the harness works;
- a trivial `WriteLn` program prints and exits 0.

So the trap is the assignment, and it is at **program level** — no procedure, so
no frame, no scope-exit release, nothing this could share with the managed-local
leak it was found beside.

## The compiler already says why

`WasmUnsupported` does not print at the trap; it records a reason and the
backend lists every broken body at COMPILE time. That list says:

```
    main$0 — statement IR op 43
```

`defs.inc:910`: `IR_VAR_STORE = 43`. The report was there the whole time and the
first reading of this defect (a table row saying "Variant: trap, exit 134") came
from running it rather than from reading what the compiler had already printed.

## Scope

| op | wasm32 | riscv32 |
| --- | --- | --- |
| `IR_VAR_STORE` (43) | 0 | 2 |
| `IR_VAR_BINOP` (44) | 0 | 2 |
| `IR_VAR_BOX` (45) | 0 | 2 |

Three ops. Port from riscv32 or aarch64. The one wasm32-specific piece: any
Variant op needing the address of an RTTI blob must go through the
descriptor-cell indirection (`WasmRecDescAddr`, `ir_codegen_wasm32.inc`), because
this backend has no code→data fixups and emits every address inline as a
constant — the blob's offset does not exist while bodies are being emitted.

## Do not read the PXXVarClear arm as coverage

`74e33af46` gave wasm32's scope-exit release a Variant arm alongside the four
others it fixed. It is written to the same shape as every other backend's and it
has **never executed**, because no program can get a Variant into a local
without tripping the trap above. When this lands, that arm is the first thing to
measure — a `Variant` local holding a runtime-built string, 300 iterations,
`-dPXX_ALLOC_CENSUS`, against x86-64.

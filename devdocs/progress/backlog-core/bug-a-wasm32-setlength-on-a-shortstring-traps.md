---
slug: bug-a-wasm32-setlength-on-a-shortstring-traps
track: A
prio: 60
type: bug
status: open
blocked-by: []
found: 2026-09-02
found-by: frankC
owner:
summary: "SetLength on a shortstring traps on wasm32 (`wasm trap: unreachable`, rc=134). Correct on riscv32 and x86-64; reproduced under the PINNED compiler, so it predates the phase-2 shortstring work. This is the cause of three of the five rows excluded from test-wasm32 -- test_cross_sets, test_frozen_string_cross_b305 and test_static_string_literal all die at 134 through this path, so it is not a corner case reached only by a probe."
---

# SetLength on a shortstring traps on wasm32

## Repro

```pascal
type TS = string[8];
var s: TS;
begin s := 'abcde'; SetLength(s, 1); WriteLn('len=', Length(s)); end.
```

```
wasm32   wasm trap: unreachable   rc=134
riscv32  len=1
x86-64   len=1
```

## Why it is worth a ticket rather than a note

Three real suite tests reach it — `test_cross_sets`,
`test_frozen_string_cross_b305`, `test_static_string_literal` — all rc=134.
It is on the ordinary path, not a shape only a probe produces.

## Controls already run

- PINNED compiler reproduces -> predates phase 2 and any local tree.
- riscv32 and x86-64 correct -> wasm32-only.

## Related

[[bug-a-wasm32-shortstring-comparison-is-wrong-at-every-length]] — found in the
same sweep, same layout, also a reader rather than a writer. Worth checking
whether one cause covers both before fixing either.

`compiler/ir_codegen_wasm32.inc` was under active edit by frankwasm (phase-2
byte-prefix conversion) when this was filed, so it was filed rather than fixed
— topic collision, not lack of authority.

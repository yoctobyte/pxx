---
track: A
tags: [wasm32, nilpy, generator]
prio: 40
type: bug
status: open
owner:
blocked-by: []
summary: "`def g(n): yield 1` then `print(list(g(2)))` traps on wasm32 with `wasm trap: indirect call type mismatch`. x86-64 prints [1]. A `for x in g(n)` loop over the same generator works on wasm32, so the fault is in how list() drives the generator."
---

# list() of a NilPy generator traps on wasm32

Found 2026-11-19 by claude-dupwt while reducing
bug-a-a-nilpy-generator-slice-faults-out-of-bounds-under-wasm32, which had a
different cause.

```python
def g(n):
    yield 1

print(list(g(2)))
```

wasm32 (wasmtime): `wasm trap: indirect call type mismatch`. x86-64: `[1]`.
`for x in g(3): print(x)` works on wasm32.

A type mismatch at call_indirect means the call site's type index differs
from the table element's real signature. WasmSigForProcSelf's header
describes the Self-parameter case of exactly that. Likely suspect: list()
calls the generator's step/next routine through a procvar whose signature
proc does not match the step function it is given.

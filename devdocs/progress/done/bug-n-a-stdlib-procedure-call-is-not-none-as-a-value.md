---
track: N
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankuser (2026-09-29; `print(random.seed(1) is None)` printed False)
tags: [nilpy, stdlib, codegen]
summary: "A stdlib call that maps onto a Pascal procedure (random.seed, random.shuffle, sys.setswitchinterval) read whatever was in the result register when used as a value: `random.seed(1) is None` printed False, `x = random.seed(2)` gave 2. It is now None, as in CPython. Those three and sys.exit are the only procedure-backed entries of PyStdlibCallProc's 76."
owner: ""
---

# A stdlib call backed by a Pascal procedure is not None as a value

```python
import random
print(random.seed(1) is None)   # v451: False (CPython True)
x = random.seed(2)              # v451: x == 2
```

## Cause

`PyParseStdlibCall` typed the call node with the procedure's `RetType`.
A procedure has none, so a value use read a stale register.

## Fix (compiler/pyparser.inc)

When the shim is not a function, the call becomes `(call, None)`: an
`AN_COMMA` whose value is `PyMakeNone`. A class method with no result
already works this way.

## Census

Of the 76 entries of `PyStdlibCallProc`, 4 are Pascal procedures:
`sys.exit`, `sys.setswitchinterval`, `random.seed` and `random.shuffle`.
The census grepped `procedure <name>` in compiler/ and lib/. `sys.exit`
never returns, so it has no value to see. The fixture covers the other
three, both as values and as statements.

## Rows

test/test_nilpy_stdlib_procedure_call_is_none.npy, with its .expected
taken from CPython. Rows: x64 (procnone26), wasm32 and i386. All three
are red on the compiler before the fix.

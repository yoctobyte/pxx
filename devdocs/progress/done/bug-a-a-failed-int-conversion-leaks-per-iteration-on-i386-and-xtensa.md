---
track: A
prio: 50
type: bug
blocked-by: []
summary: "FIXED 2026-09-24 (frankH). The leak was never on int()'s ERROR path. It was the string LITERAL argument: a successful `int(\"12\")` leaked the same one block per call. The call-argument arm of the i386, riscv32 and xtensa backends turned a literal handed to a managed-string parameter into a fresh heap copy (PXXStrFromLit), which is an owned +1 that nothing released after the call. The mechanism: a backend fallback that materialises a managed string at a call argument, reached by a frontend (NilPy int() -> pystr_to_promo) that does not convert the argument in IRLowerCallArg first. Pascal converts it there and never reached the fallback. arm32 already returned the literal's static handle. Now all three do the same. Verified by the census on i386 (live 2888 -> 2; test/test_nilpy_literal_arg_no_leak.npy row in test-i386, pinned-compiler control live=5840), by free-heap delta on the ESP32-S3 board (44 -> 0 bytes/iter for both shapes, plain-loop control 0), and on riscv32 by objdump (the PXXStrFromLit call before pystr_to_promo is gone; hosted riscv32 cannot run NilPy)."
status: done
---

# A failed int() leaks per iteration on i386 and xtensa, not on arm32/x86-64

## Repro (HEAD 6eaabf48c + VMT fix)

```python
i = 0
c = 0
while i < 3000:
    try:
        v = int("x")
    except ValueError:
        c = c + 1
    i = i + 1
print(c)
```

`pascal26 -dPXX_ALLOC_CENSUS --target=<t> exc3k.npy exc3k`, then run it:

| target | allocs | frees | live | notable size classes |
| --- | --- | --- | --- | --- |
| x86-64 | 19780 | 19776 | 4 | 56, 72, 128 |
| arm32 (qemu-arm) | 19780 | 19776 | 4 | 48, 56, 72, 128 |
| i386 | 22253 | 19468 | **2785** | **32:2782**, 48, 56, 72, 128 |

- **i386** makes about 2,470 extra allocations of 32 bytes (roughly 0.8 per iteration) and never frees them.
- **ESP32-S3 (QEMU, IDF heap):** OOM between the 4,000 and 6,000 progress prints. Since this morning's heap_caps change it reports `pxx: out of memory (ESP-IDF heap exhausted)`; before that it was a bare `StoreProhibited` at address 0.

## Next step

Compare the i386 and arm32 builds and find what i386 allocates at 32 bytes on this path that arm32 does not. A string or promo temp on the exception-message route is the first suspect, since pystr_to_promo builds the message. Then check whether xtensa takes the same route. The test above is the population; a fix needs an `assert_no_leak.sh` row on i386, because no output comparison can see a leak.

Found 2026-09-24 (frankH) by the NilPy board census on an ESP32-S3.

## Resolution, 2026-09-24 (frankH)

The ticket's premise was wrong. `int("12")` leaked exactly as `int("x")` did, and `int(s)` with a variable did not leak: `s` is a Variant there, so it takes the pyint_v route. The leak was in how the literal ARGUMENT was materialised, not in the error path.

- **i386:** `ir_codegen386.inc`'s call-argument arm for a frozen string into a tyAnsiString parameter now tries EmitStaticLitHandle386 first.
- **riscv32:** `EmitAnsiStringFromNodeRISCV32` now has an IR_CONST_STR arm.
- **xtensa:** `EmitAnsiStringFromNodeXtensa` now has an IR_CONST_STR arm. Note that xtensa has TWO such helpers. The store helper, EmitStrHandleForStoreXtensa, already had the static-handle arm; the argument helper did not. Reading the store one first led me to conclude xtensa was already fixed, and the board said otherwise.

Measured, not assumed:

| target | instrument | before | after |
| --- | --- | --- | --- |
| i386 | census, 3000 iterations | live 2888 / 2785 | 2 / 4 |
| ESP32-S3 board | free-heap delta, 1000 iterations | 44 B/iter | 0 (plain-loop control: 0) |
| riscv32 IDF | objdump of the loop | 1 PXXStrFromLit call | 0 |

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

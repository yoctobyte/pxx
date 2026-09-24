---
track: A
prio: 50
type: bug
blocked-by: []
summary: "A failed `int(\"x\")` caught by `except ValueError` leaks one heap block per iteration on some 32-bit backends, not all. Measured with the -dPXX_ALLOC_CENSUS allocator census, as allocs/frees over 3000 iterations: i386 leaks 2785 live blocks, all in the 32-byte size class; arm32 and x86-64 leak 4 (the same 4 as a clean run). On the ESP32-S3 (xtensa) the same loop exhausts the IDF heap in about 4,000–6,000 iterations under QEMU, so xtensa leaks as well; its census cannot run there, so the size is unmeasured. A plain `raise ValueError(...)` in the same loop does not leak on the S3, which puts the leak on int()'s own error path (pystr_to_promo → Exception.Create), not on raise/except. Reached by test/test_nilpy_exception_no_leak.npy (n=640000), which prints the right count wherever memory lasts and so cannot see the leak on a host."
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

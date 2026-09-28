---
track: A
prio: 55
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "On hosted arm32, Nil Python `int(3000000000.7)`, `math.floor`, `round` and `trunc` saturated at 2147483647, `time.gmtime` of a real timestamp was wrong, and float repr differed in the last digits. The hosted arm32 build never pulled the softfloat unit that riscv32 and xtensa pull, so float-to-Int64 went through a 32-bit VFP conversion."
owner: ""
---

# arm32: Nil Python float-to-int saturates at 32 bits

```python
big = 3000000000.7
print(int(big), round(big))   # arm32: 2147483647 2147483647; expected 3000000000 3000000001
```

Also differing on arm32 only: `lib_mimic_time_calendar` (gmtime of a current
timestamp) and a float repr (`0.47942553860420301`).

## Fix

`PullSoftFloatBeforeBuiltinHeap` in `frontend_prologue.inc` now pulls `softfloat`
for `TARGET_ARM32` as well.

## Side effect found and fixed

Pulling softfloat changed what an arm32 float compare leaves in r1. That exposed
bug-a-a-host-method-result-is-read-past-its-width-on-32-bit-targets:
`test_nilpy_open_world_method_dispatch` flipped from same to DIFF on arm32. It is
fixed in the same change.

## Test

`test/test_nilpy_cross32_values.py` (the float-to-int block), with a row in
`test-arm32`. Measured wrong with pin v446 (`stable_linux_amd64/default/stable_pinned`) on 2026-09-28.

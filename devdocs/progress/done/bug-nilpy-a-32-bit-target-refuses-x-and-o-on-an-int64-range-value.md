---
track: A
prio: 45
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "On i386 and arm32, `'%x' % -2**63`, `'%o'` and `format(v, 'x')` of an Int64-range value past 32 bits raised (exit 217). On a 32-bit target that int is already arbitrary-precision and reached PyFormatIntEx as a decimal string, which is refused for every base but 10."
owner: ""
---

# A 32-bit target refuses %x and %o on an Int64-range value

`test/nilpy_low_int64_boundary.py` exited 217 on i386 and arm32 and matched
CPython on x86-64 and aarch64.

```python
print("%x" % -2**63, "%o" % (2**63 - 1), format(2**63 - 1, "x"))
```

## Mechanism

On a 32-bit target a promotable int beyond 32 bits is arbitrary-precision, so
`PyFormatIntEx` received it as `bigDec`, a decimal string. The big path handles
only base 10, so every other spec raised.

## Fix

In `pylib.pas`, `PyDecFitsInt64` parses the decimal exactly, and a value that
fits in an Int64 takes the machine path on every target. A value that really is
wider is still refused, as it is on x86-64.

## Test

`test/test_nilpy_cross32_values.py` (the `%x` block), with rows in `test-i386`
and `test-arm32`. Measured wrong with pin v446 (`stable_linux_amd64/default/stable_pinned`) on 2026-09-28.

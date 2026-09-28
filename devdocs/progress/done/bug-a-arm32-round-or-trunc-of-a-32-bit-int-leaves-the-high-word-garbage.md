---
track: A
prio: 50
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "On arm32, Round/Trunc of a 32-bit INTEGER argument (Nil Python `round(7)` on a literal) returned an Int64 whose high word was never set: `round(7)` printed 582096337806295047. The intrinsic arm left r0 alone ('r0 already holds the value'), where i386 widens with cdq."
owner: ""
---

# arm32: round or trunc of a 32-bit int leaves the high word garbage

```python
print(round(7))   # arm32: 582096337806295047; x = 7; round(x) was fine
```

These rows differed: `test_nilpy_round_keeps_intness` and
`test_nilpy_round_ndigits_keeps_int` (`round(7)` gave -4294967289 there).

## Fix

In the `ir_codegen_arm32.inc` intrinsic 203/204 integer-argument arm, when the
result is 64-bit and the source is not, the source's signedness decides:

- signed source: `mov r1, r0, asr #31`;
- unsigned source: `mov r1, #0`.

## Test

Rows for both round tests in `test-arm32`. Wrong with v446 and p447.

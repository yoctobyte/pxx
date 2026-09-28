---
track: A
prio: 35
type: bug
blocked-by: []
status: open
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "On arm32, `from time import sleep as sf; sf(0.0)` (or `sf(0)`) never returns, while `from time import sleep; sleep(0)` returns at once. aarch64 and i386 are fine. It is the same with v446 and fad87004e4e8. Found as the TIMEOUT of test_nilpy_an_if_decided_at_compile_time_skips_its_dead_arms on arm32."
owner: ""
---

# arm32: a from-import alias of time.sleep hangs

```python
from time import sleep as sf
print("a")
sf(0.0)          # arm32: never returns (timeout, rc=124)
print("b")
```

`from time import sleep` followed by `sleep(0)`, `sleep(0.0)` or `sleep(1)`
works on arm32. The alias is the boundary. `time.sleep` is
`procedure sleep(seconds: Double)` in `lib/rtl/mimic_time.pas`, so the suspect
is how the aliased call hands its Double argument over on arm32 (d0 versus
r0:r1), giving the callee a huge duration.

Found by the 2026-09-28 differential: it is why
`test_nilpy_an_if_decided_at_compile_time_skips_its_dead_arms` times out on
arm32.

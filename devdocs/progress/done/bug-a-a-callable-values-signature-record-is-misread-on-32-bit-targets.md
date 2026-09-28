---
track: A
prio: 55
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "On 32-bit targets a def called back through a callable value misread its signature record: `f = q; f(1)` printed `(, 1)` on i386, a *args call segfaulted, and arm32 read the wrong Names word. TPySigRec declared pointer-sized fields, while the compiler writes the record at the fixed 0/8/16/24/32/40 offsets of PYSIG_OFF_*."
owner: ""
---

# A callable value's signature record is misread on 32-bit targets

```python
def q(a, b=7):
    return (a, b)
f = q
print(f(1), f(1, 2))        # i386: (, 1) ...; expected (1, 7) (1, 2)
def star(*args):
    return len(args)
h = star
print(h(1, 2, 3), h())      # i386: segfault
```

## Mechanism

The compiler writes the signature record at the fixed offsets `PYSIG_OFF_*` in
`defs.inc`, where every field is one 8-byte word. The runtime's `TPySigRec` in
`pylib.pas` declared `Code`, `Dflts` and `Names` as pointers, which are 4 bytes
on a 32-bit target, so every field after the first was read 4 bytes early.

## Fix

Under `CPU32`, `TPySigRec` pads each pointer field to 8 bytes (`CodePad`,
`DfltsPad`, `NamesPad`).

## Test

`test/test_nilpy_cross32_values.py` (the callable block), with rows in
`test-i386` and `test-arm32`. Measured wrong with pin v446 (`stable_linux_amd64/default/stable_pinned`) on 2026-09-28.

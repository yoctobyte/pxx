---
track: N
prio: 30
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "On i386, the default object repr printed a heap address with the top bit set as a NEGATIVE hex number (`<__main__.Plain object at -0x358f3fa8>`), and an iterator repr printed no digits at all. The pointer went through NativeInt into Int64 and was sign-extended."
owner: ""
---

# A 32-bit object repr prints a negative address

`test_nilpy_container_element_repr` differed on i386 only. Its shape check
`s.startswith("[<__main__.Plain object at 0x")` was False.

## Fix

In `pylib.pas`, both address formatters zero-extend through `NativeUInt`: the
default object repr and `pyiter_repr` (whose loop printed nothing for a
negative value).

## Test

A row in `test-i386` and in `test-arm32` for `test_nilpy_container_element_repr`.

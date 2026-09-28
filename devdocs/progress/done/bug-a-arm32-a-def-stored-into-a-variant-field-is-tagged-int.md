---
track: A
prio: 50
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "On arm32 a def stored into a Variant field, or boxed into a Variant operand, was tagged int, so calling it back through the field failed. The three test_nilpy_callable_field_* tests differed on arm32 only. The arm32 IR_VAR_STORE and IR_VAR_BOX arms took the tag from VariantTagForTk and never asked IRSrcIsCallable, which every other backend does."
owner: ""
---

# arm32: a def stored into a Variant field is tagged int

`test/test_nilpy_callable_field_all_shapes.npy`, `..._call_returns.npy` and
`..._wide_arity.npy` matched x86-64 on i386 and aarch64, and differed on arm32.

## Fix

In `ir_codegen_arm32.inc`, both arms now override the tag with `VT_CALLABLE_TAG`
when `IRSrcIsCallable` is true, the same line every other backend has.

## Test

Rows for the three tests in `test-arm32`. Measured wrong with pin v446 (`stable_linux_amd64/default/stable_pinned`) on 2026-09-28.

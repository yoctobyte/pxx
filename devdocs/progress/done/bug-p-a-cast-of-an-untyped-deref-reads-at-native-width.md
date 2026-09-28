---
track: P
prio: 60
type: bug
status: done
found: 2026-09-28
found-by: frankD
owner:
summary: "SILENT. A value cast of UNTYPED memory read at native width and then converted: `Int64(p^)` / `QWord(p^)` over a bare Pointer, and `Int64(v)` of an untyped const/var parameter, read 4 bytes on i386/arm32/riscv32 (705032704 for 5000000000); `Double(p^)`, `Single(p^)` and `Double(v)` converted the integer bytes to a float on EVERY target (4609434218613702656.000 for 1.5). v446 (ae3466a018d8) the same. Typed pointers, the cast-as-lvalue STORE and `PInt64(p)^` were right."
---

# A cast of an untyped deref reads at native width

Found by the Pascal cross-target differential (the test corpus, pxx x86-64 as
the reference, FPC as the third arm): test_cast_as_lvalue_builtin_names'
`Int64(p^)` row differed on i386, arm32 and riscv32. Widening the probe to the
float kinds showed the same defect wrong on the 64-bit targets too.

## Resolution (2026-09-28)

An untyped `p^` is an AN_DEREF tagged tyUnknown, and an untyped parameter is
declared tyPointer by reference; each backend loaded either at native width and
the cast then CONVERTED that value. FPC reinterprets the memory at the cast's
width. TryScalarNamedCast, the shared construction half of every named scalar
cast, now stamps an untyped deref with the cast's kind, and rewrites an untyped
parameter into the `PT(@v)^` deref that FinishCastAsLValueStore already builds
for the store side -- one shape for the read and the write.

Fixture `test/test_a_cast_of_an_untyped_deref_reads_at_the_casts_width.pas`
(Int64/QWord/LongInt/Word/Byte/Double/Single/enum over p^, in an expression,
an assignment, a comparison, a store; const Int64/QWord/Double and a var
read-modify-write through untyped parameters; .expected by FPC 3.2.2), in
test-core native and i386/aarch64/arm32/riscv32. v446: 3 rows wrong on the
64-bit targets, 11 on the 32-bit ones; this build none.

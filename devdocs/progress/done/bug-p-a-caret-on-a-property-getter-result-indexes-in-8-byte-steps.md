---
track: P
prio: 60
type: bug
status: done
found: 2026-09-28
found-by: frankD
owner:
summary: "SILENT, every target. `c.L^[i]` over `property L: PIA read GetL` (PIA = ^array[..] of Integer) indexes in 8-byte steps: c.L^[1] reads element 2 (50 where FPC reads 30), a Word array reads 0, and `c.L^[2] := v` writes the wrong element. TList's `list.List^[i]` is the same shape -- right on 64-bit only because a Pointer is 8 bytes, wrong on i386/arm32/riscv32 (lib_classes list-List-alias). v445 (caf21ac399f1) the same. The method spelling, a parenthesised (c.L)^[i], a cast and a field-backed property were right."
---

# A caret on a property getter's result indexes in 8-byte steps

Found by the Pascal cross-target differential (the Pascal test corpus, pxx
x86-64 as the reference, FPC as the third arm): lib_classes'
`list-List-alias` row failed on i386, arm32 and riscv32 only. Reducing it
showed the defect is not target-specific at all -- for any element but
Pointer/Int64 it is wrong on x86-64 too; Pointer elements on a 64-bit target
were right by coincidence.

## Resolution (2026-09-28)

ParseLValueAST's instance property arm dereferenced a METHOD getter's result
with its own loop, which tagged every AN_DEREF tyInt64 with no pointee shape
("read as Int64, an outer ordinal cast narrows" -- written for fgl's untyped
`T(FList.Items[i]^)`). A typed pointee now goes through the shared
StampDerefFromShape, as the other postfix walks' carets do; the untyped case
keeps the old tag.

Fixture `test/test_a_caret_on_a_property_getter_result_keeps_the_pointee.pas`
(Integer/Word/Byte/Int64/Double/Pointer/record elements, a variable index, a
write-through, a record pointee, `^^`, the untyped case; .expected by FPC
3.2.2), in test-core for native, i386, aarch64, arm32 and riscv32. v445: 5 rows
wrong on x86-64, 7 on i386 (and it refuses the record rows); this build none.

Seen on the way, not fixed here (a refusal, not a wrong value):
`@list.List^[0]` is "expected ')' before '^'".

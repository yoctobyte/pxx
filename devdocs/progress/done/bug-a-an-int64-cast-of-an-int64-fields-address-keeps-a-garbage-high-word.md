---
track: A
prio: 60
type: bug
status: done
found: 2026-09-28
found-by: frankD
owner:
summary: "SILENT, i386/arm32/riscv32. `Int64(@r.f)` where f is an Int64/QWord/Double field kept a garbage high word: `Int64(@r.i) - Int64(@r)` was 4294967297 for a field at offset 1 (FPC 1), and on arm32/riscv32 even `x := Int64(@r.i)` was wrong. test_record_layout_stress's offset rows failed there for this reason, not for layout. v446 (ae3466a018d8): 6-7 of 8 fixture rows wrong on each."
---

# An Int64 cast of an Int64 field's address keeps a garbage high word

Found by the Pascal cross-target differential: test_record_layout_stress
failed packed-record offset rows (8, 16, 29) on arm32 and riscv32, where no
ABI could move a packed field. The layout was right; the offset arithmetic was
not.

## Resolution (2026-09-28)

`@r.i` lowers to an IR_FIELD tagged with the FIELD's kind (the pointee, which
IRValueKind documents). The AN_PTR_CAST lowering asked IRTk whether the operand
was "already 64 bits", got Int64, and skipped the widen; the 32-bit pair path
then read the address node as an Int64 pair. The widen test now asks
IRValueKind, and inside the widen the freshly lowered address operand is
retagged tyPointer (as IRLowerDestAddress already does) so the pair path
zero-extends it.

Fixture `test/test_an_int64_cast_of_a_fields_address_widens_the_pointer.pas`
(.expected by FPC 3.2.2), in test-core native and cross. The remaining
test_record_layout_stress rows on i386 are the psABI's 4-byte member alignment
of Int64/Double (TypeFieldAlign, deliberate), not this.

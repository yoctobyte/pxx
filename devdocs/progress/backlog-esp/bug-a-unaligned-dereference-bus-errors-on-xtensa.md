---
track: A
prio: 40
type: bug
blocked-by: []
summary: "test/test_p_unaligned_is_a_transparent_lvalue.pas dies with SIGBUS on hosted xtensa, windowed and call0, at -O0 and -O2. Its first row, R01 'read dword', faults. An Unaligned(PDWord(p)^) read is emitted as a plain l32i, which faults on a misaligned address on xtensa. Packed-record fields already take the byte path (XtensaAddrIsRagged); Unaligned() through a pointer does not. It is pre-existing: the compiler at fd876a1891 does the same. Found 2026-11-12 while checking the field-offset fold, which does not touch it."
status: open
owner: unassigned
---

# Unaligned() dereference bus-errors on xtensa

## Found

On 2026-11-12, while checking that the xtensa field-offset fold leaves ragged
accesses alone, the test above was run against the x86-64 oracle on hosted
xtensa:

- x86-64 prints `R01 read dword ok` and the rows after it.
- Xtensa dies with SIGBUS before printing anything.
- It fails on windowed and on call0, at -O0 and at -O2.
- These compilers all fault the same way:
  - fd876a1891 (before today's xtensa work);
  - 4bed25835b;
  - the field-offset fold build.

The test has no xtensa rows in test-xtensa, which is why nothing caught it.

## Where to look

Ragged record fields are handled from the address node: XtensaAddrIsRagged
reads the IR_FIELD bit set in ir.inc, and EmitUnalignedLoadXtensa /
EmitUnalignedStoreXtensa do byte accesses. `Unaligned(...)` reaches the load
through a pointer, so no IR_FIELD carries the bit. Either the intrinsic marks
its access for the byte path, or the xtensa load/store arms learn to recognise
it.

The ESP chips fault on misaligned l32i/l16i the same way qemu does, so this
matters on hardware as well.

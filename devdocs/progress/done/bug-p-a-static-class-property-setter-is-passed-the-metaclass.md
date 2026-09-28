---
track: P
prio: 60
type: bug
status: done
found: 2026-09-28
found-by: frankD
owner:
summary: "A `static` class method has no Self, but three call builders still headed its argument chain with one: a class property's accessor through the class name (`TD.Level := 7`), a property accessor through an INSTANCE (`R.P := 3`, MakeAccessorCall), and a bare call inside `with` (`with R do Add(4)`). x86-64 and aarch64 ignored the extra argument register; i386/aarch64/arm32 refused (\"call argument count mismatch\") and riscv32 SILENTLY passed the receiver as the first parameter (`after : TRUE 134555768`, `6 6`, `7 10 10`). v446 the same."
---

# A static class-property setter is passed the metaclass

Found by the Pascal cross-target differential: test_class_property_b299,
test_class_property_indexed and
test_a_records_static_class_method_is_reachable_through_an_instance failed to
build on three cross targets and printed wrong values on riscv32.

## Resolution (2026-09-28)

GenMakeStaticMethodCall already had the rule (`if ProcNoSelf[mpi] then
selfNode := -1`). The three hand-rolled builders now apply it: the
class-qualified class-property arm and the with-scoped method arm in
ParseLValueAST, and MakeAccessorCall (which serves every instance receiver).
All three tests now run cross in test-core and match on all five targets.

Seen, not fixed here: the with-scoped method arm passes the with OPERAND as Self
to a non-static CLASS method too, where Self should be the metaclass; not
measured wrong yet.

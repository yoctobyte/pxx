---
track: A
prio: 10
type: bug
blocked-by: []
status: done
found-by: frankd-23 (contnrs TFPObjectList with OwnsObjects never destroyed its items), via frankuser; located by frankH
tags: [pascal, class, destructor, unit, leak, contnrs, cross-target]
summary: "Inside a UNIT, `TObject(p).Free` and `o.Free` on a TObject-typed receiver ran FreeMem alone, so an overridden destructor never ran. fpc runs it, and so did the same code in the program file. The Free desugaring called Destroy only when the class had a Destroy ROW, and in a unit TObject has none while the unit's bodies parse: the program mints it at the end of pass 1, and the unit pre-scan deliberately doesn't. The three Free builders now share GenMakeDestroyCall. When there is no row, it dispatches through the reserved ROOT_VMT_DESTROY slot, which FillRootVMTSlotDefaults always fills with the override or the empty default."
owner: ""
---

# Free on a TObject in a unit skips the overridden destructor

```pascal
unit u;            procedure FreeObj(p: Pointer); begin TObject(p).Free; end;
program p;         TThing = class destructor Destroy; override; end;
                   FreeObj(Pointer(TThing.Create));   { pxx: 0 destructor calls, fpc: 1 }
```

contnrs frees its items that way, so a `TFPObjectList.Create(True)` leaked
everything its items' destructors owned: Delete, Clear and Free destroyed
0/0/0 where fpc destroys 1/5/8.

## Why the row is missing

EnsureTObjectRootMethodsEx(False), the unit pre-scan's variant, mints Equals,
GetHashCode and ToString, but not Destroy, because an early Destroy row was
measured to corrupt the heap (bug-a-minting-tobject-root-methods-from-a-unit-corrupts-the-heap,
still open). The program mints Destroy at the end of pass 1, after every unit
body has already been compiled. GenMakeFreeObject, GenMakeFreeObjectField and
GenMakeFreeObjectExpr each asked `FindUMeth(ci, 'Destroy') >= 0` and emitted
no call when the answer was no.

## Fix

GenMakeDestroyCall is the one decision the three builders now share. A
Destroy row gives the method call, as before. With no row, for a class
receiver, when the root slot exists (not --compact-classes) and
__pxxTObjectDestroy is present, it builds an AN_VIRTUAL_CALL on
ROOT_VMT_DESTROY with that body's signature (Self only). That is the call the
program path's row produces, and it mints nothing.

## The slot must be filled on every frontend

Only Pascal's ParseProgram called FillRootVMTSlotDefaults. A NilPy program
(and a C one) left the reserved root slots nil, and pylib/pyeval are Pascal:
their `args.Free` on a TPyList now dispatched slot 0 and jumped to address 0.
The first build of this fix crashed uforth and `sorted([3, 1, 2])`. The NilPy
and C epilogues now fill the slots too. That also covers the exception
handler's destructor dispatch (ir.inc), which already read this slot and was
a latent nil jump in a NilPy program. The builder also skips a class with
fewer virtual slots than the root reserves, as the filler does.

## Tests

- test_free_on_a_tobject_in_a_unit_runs_the_destructor, with the helper unit
  tobject_free_unit: the unit's cast Free, the unit's typed Free, and the
  program control. Its expected output is fpc 3.2.2's. It passes on six
  targets; before the fix, the two unit rows gave 0.
- test_an_owning_object_list_counts_its_destructors: TFPObjectList(True)
  Delete/Clear/Free prints 1 5 8, matching fpc, on six targets. It was 0 0 0.
- test_an_owning_object_list_destroys_its_items: a census row with 3000 items,
  each owning a TInner. The fix ends at 31 live blocks (bound 200); the `keep`
  control and the old compiler both end at 5431.
- test_nilpy_runtime_free_lands_on_a_filled_destroy_slot: sorted(), a def
  through a variable, and a method called from exec'd code. It equals CPython
  on x86-64 and i386; without the epilogue fill it segfaults.

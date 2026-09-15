---
track: N
prio: 85
type: bug
blocked-by: []
summary: "`acc.force += v` where `acc` is an UNANNOTATED parameter and the field holds a user-class instance never called the dunder: the variant-receiver field store built a raw class-typed binop over two instance handles. 0.0 read back, or a segfault with `v` annotated. The demo's accumulator idiom (`state.velocity += x`). FIXED 2026-09-15 with three sibling rows of the same store."
status: done
---

# An augmented store into a class field of a variant receiver never reaches the dunder

Found by the lekkerzeilen seat (2026-09-15) while trying to reproduce a leak
attribution: `acc.force += v` through an unannotated parameter raised
`TypeError: expected a number, got object` on 1a74a2318642. Varying the shape
here: with `acc` annotated it is correct; unannotated it reads back 0.0 (the
dunder never called) or, with `v: Vec3` or a read of the field in the same
body, SEGFAULTS. CPython prints 2.0 for all of them.

**Mechanism, read.** `PyMakeVariantFieldSet` dispatches a write through a
variant receiver per candidate class (`if pyvarobj(v) is C then
C(pyvarobj(v)).name := ...`). Its per-arm builder `PyVariantFieldStore` built
the augmented form as a bare `AN_BINOP` typed with the field's kind -- for a
class-typed field, a class-typed add of two instance pointers. The bare-name
target (`PyAugClassDunder`) and the statically typed field target
(`PyAugClassDunderNode`) both dispatch `__i<op>__`/`__<op>__`; this was the
THIRD arm of one family and the one left behind (`normalise-dont-special-case`).

**Three sibling rows in the same store, fixed together:**
- the PLAIN store of a variant into the class field (`acc.force = acc.force +
  v`, or `= f` with `f` bound from the read) stored the raw variant record into
  the class slot -- 0.0 or a segfault -- now unboxed, the field twin of
  `PyStoreRhsToClassSlot`;
- the DYNAMIC fallback arm (a receiver whose class is not a candidate) stored
  the raw right-hand side for an augmented store, so `b.n += 5` left `b.n`
  holding 5 -- now a read-modify-write through `pydynattr_get_v`;
- a LIST field extended through a variant receiver (`b.xs += [2]`) segfaulted
  -- now the in-place `extend`, the typed target's rule.

**And a fourth thing the census found, which the value rows could not:** both
unboxes were first written OWNED, on the strength of the comment in
`PyStoreRhsToClassSlot` (landed the same day): "without the retain the slot
points at a freed block". Traced with `-dPXX_OBJTRACE`, the store into a
class-typed slot RETAINS by itself, so the owned unbox was a second +1 nobody
released: `g: Vec3 = mk()` leaked one object per call, 921 allocs / 0 frees,
with the value correct and its fixture green. Both sites are bare unboxes now;
the comment is corrected in place. `test/test_nilpy_a_class_annotated_local_from_a_call_is_released.npy`
is the census row that guards it (live=4 over 3000 stores; HEAD before the
fix: leak or segfault).

Fixture: `test/test_nilpy_an_augmented_store_into_a_class_field_of_a_variant_receiver_reaches_the_dunder.npy`,
eleven rows, every expected value chosen to differ from the raw right-hand
side and from 0, byte-identical to CPython, identical under `-dPXX_HEAP_DEBUG`.
A demo-shaped probe (`state = self.state; state.velocity += ...` on a typed
`self`, and `body.state.velocity += ...` through a variant) matches CPython.

**Why 85 and not filed lower:** the demo's contributor loop is this shape.
The leak half is NOT offered as the 16 MB ticket's residual: the lekkerzeilen
seat's static census of the demo's source as of 2026-09-15 finds exactly two
annotated-local assignments, both `: int`, which never reach the unbox at
all. That is a census of the source on that date -- the idiom is absent, not
prohibited -- so the exculpation is worth exactly as long as nobody writes
`v: Vec3 = body.state.velocity.copy()` in the integrator, and the census row
is what guards it after that.

## Log

- 2026-09-15 frankuser (Fable): found from the lekkerzeilen seat's TypeError repro, shape varied into four faces, fixed with three sibling rows and the owned-unbox leak, commit 3a91d13f1. Runtime dispatch half of the same evening: 0badcd665.

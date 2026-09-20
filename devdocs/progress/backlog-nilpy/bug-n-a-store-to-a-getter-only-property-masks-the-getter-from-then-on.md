---
slug: bug-n-a-store-to-a-getter-only-property-masks-the-getter-from-then-on
type: bug
track: N
prio: 45
status: open
summary: "A store to a property that has a getter and NO setter falls through to the dynamic-attribute store, and because pydynattr_get consults that store BEFORE the property, every subsequent READ of that name returns the stored value instead of calling the getter. The defect is the MASKING, not the acceptance: a computed property silently becomes a stale data field, and a read that was correct before the write is wrong after it. Springs whenever a program assigns to a read-only property on a receiver whose class the frontend cannot name."
owner:
---

# A store to a getter-only property masks the getter from then on

## The condition that springs it

A class declares `@property def x` with **no** `@x.setter`. A store
`recv.x = v` reaches `pydynattr_set` — which it does whenever the frontend
cannot name `recv`'s class, and also whenever the field-wins precedence loop in
`PyVariantPropClass` hands the name to an unrelated class (see
`done/bug-n-a-field-of-the-same-name-in-an-unrelated-class-defeats-a-property-setter-on-a-bare-receiver`).

`PyPropertySet` finds no `__prop_set_x`, correctly declines, and the store falls
through to the shadow attribute. `pydynattr_get` then consults that shadow
**first** — before declared fields and before `PyPropertyGet`.

## Why this is a defect and not Track N's upward compatibility

**It would be easy to file this as a feature and that would be wrong.** The rule
is that NilPy is upward compatible with CPython in one direction, and accepting
what CPython rejects is a feature — CPython raises `AttributeError: can't set
attribute` here and we do not. **If accepting the store were the whole story
this ticket would not exist.**

The defect is what the accepted store does to the READ. A computed property
stops being computed: it becomes a data field frozen at whatever was last
written to it. So

- a read that was **correct before** the write is **wrong after** it, and
- the wrongness is in the getter's own answer, which the program never asked to
  change.

That is not "accepting more programs", it is **silently changing the meaning of
a construct that already worked**. A program that never reads `x` again is
unaffected; one that does gets a stale value with no diagnostic.

## Why it was left open rather than fixed with the setter

Found while writing `PyPropertySet` (2026-09-20, frankb-8e) and deliberately not
smuggled into that fix. Repairing it means choosing between:

1. **Raise**, matching CPython. Rejects programs that work today.
2. **Decline the store silently** — no shadow write, no raise. Keeps the getter
   working and loses the value. Divergent from CPython in a third direction.
3. **Reorder** `pydynattr_get` to consult the property before the shadow. Fixes
   the masking without deciding the store question, but reorders a lookup that
   several other paths depend on, including `hasattr`.

**(3) is the one to measure first** — it addresses the actual defect (the
masking) rather than the acceptance, which Track N's own rule says is not a
defect. It is also the one with the widest blast radius, so it needs the
reordering measured against `pydynattr_hasattr`, `pydynattr_get_v` and
`pydynattr_has_any_v`, which all reason about that order today.

## Not yet measured

**No fixture exists and no real program is known to hit it.** This is a
mechanism found by reading the code path while fixing its neighbour, not a
reduction from a failure — so it carries no population and should not be ranked
above anything that has one. The first piece of work is a fixture that stores to
a getter-only property on a bare receiver and then reads it back; if that turns
out to be unreachable in practice the ticket belongs in `rejected/`, and saying
so costs one afternoon.

**The sibling residual, same origin, filed nowhere else:** `PyPropertySet` and
`PyPropertyGet` both decline silently for any accessor whose value kind is
outside {Variant, int, double, string, Boolean}. The getter has carried that
since it was written. A warning at the decline would be the repair for both.

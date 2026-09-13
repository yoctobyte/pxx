---
slug: bug-n-a-class-level-method-read-off-a-class-value-as-a-value-is-refused
title: a class-level method read off a class value as a value is refused
summary: >
  `alias = Gl; alias.sm(1)` now WORKS for a @staticmethod or @classmethod, but
  READING the same member without calling it does not: `f = alias.sm` raises
  `AttributeError: type object 'Gl' has no attribute 'sm'`, `getattr(alias, "sm")`
  raises the same, and -- the dangerous one -- `hasattr(alias, "sm")` answers
  FALSE instead of raising, so guarded code silently takes the wrong branch. An
  INSTANCE method read off the same class value as a value is fine
  (`alias().inst` round-trips), so this is specifically the class-level members.
  Cause: `PyEmitClsAttrBinds` publishes class ATTRIBUTES to a runtime registry
  keyed by the class's RTTI blob -- which is what makes `alias.RENDERER` work --
  and nothing publishes METHODS, so the tag-11 read in `pydynattr_get_v` finds
  nothing. The CALL path was fixed separately and by a different mechanism (a
  direct call out of `PyParseVariantMethod`), which is why the two halves now
  disagree.
track: N
type: bug
prio: 45
owner: unassigned
status: backlog
---

## What was measured

2026-09-13 at c139938e5476. One class, one alias, seven rows, each wrapped so one
failure does not mask the rest. CPython answers every row.

    class Gl:
        @staticmethod
        def sm(a):     return "S" + str(a)
        @classmethod
        def cm(cls, a): return "C" + str(a)
        def inst(self, a): return "I" + str(a)

    alias = Gl

    row                                    CPython   pxx
    alias.sm(1)                            S1        S1      <- the CALL path, fixed
    (lambda g: g(1))(alias.sm)             S1        AttributeError: type object 'Gl' has no attribute 'sm'
    str(alias.sm is not None)              True      AttributeError: (same)
    getattr(alias, "sm")(1)                S1        AttributeError: (same)
    str(hasattr(alias, "sm"))              True      **False**
    (lambda g: g(1))(alias.cm)             C1        AttributeError: type object 'Gl' has no attribute 'cm'
    (lambda g: g(1))(alias().inst)         I1        I1      <- an INSTANCE method is fine

## The row that matters most is the `hasattr` one

Five of the six failures RAISE, which is loud. `hasattr` returns **False**, which
is not: it is a legal answer, the program continues, and a feature-detection
branch quietly takes the absent arm. That is the same class of silent wrong answer
as `bug-n-getattr-cannot-see-a-method-and-segfaults-through-a-dynamic-receiver`,
where `getattr(o, "m", None)` returned the DEFAULT and the caller's containment
test answered False for every position.

## Cause, and why the two halves disagree

Two separate mechanisms reach a member through a class held as a value:

- **The CALL path** goes through `PyParseVariantMethod`, which since 2026-09-13
  recognises a class-level-only method and emits a direct call, passing the
  variant's payload (the RTTI blob) as slot 0. It never consults any registry.
- **The READ path** goes through `pydynattr_get_v`, whose tag-11 branch consults
  the class-attribute registry that `PyEmitClsAttrBinds` fills via
  `pyclsattr_bind(<blob>, name, @slot, kind)`. That registry holds ATTRIBUTES
  only. No methods are ever published to it, so the lookup misses and the branch
  raises `type object 'X' has no attribute 'n'`.

So fixing the call did not fix the read, and it could not have.

## The fix

An analogous `PyEmitClsMethBinds(ci)` publishing the PROC ADDRESS of each
@staticmethod / @classmethod beside the attributes, and a tag-11 read that returns
it as a callable. `pyclsattr_bind` already takes a `kind`, so the registry has
somewhere to record that this entry is a method rather than a slot.

**And whatever it hands back MUST be normalised to the function-object ABI.**
`PyMethodUsedAsValue` is the gate. A method published to a registry and called
back unnormalised does not crash at the call: it answers `''` for a string,
SEGFAULTS on return for an int, and behaves **perfectly for a method returning
None**, because None needs no hidden destination. That is measured -- it is what
the literal-getattr fix had to grow `PyModuleGetattrsLiteral` for -- so a new
publication route will pass every test whose methods return nothing.

**`hasattr` and `getattr` must move together.** They are one mechanism since
`7fd25913c` routed the literal name to the same runtime resolver as the computed
one, and the whole reason that ticket existed was the two spellings disagreeing.

## Not established

What a classmethod's `cls` should bind to through this route (the registry would
have to carry the blob, which it already keys on); whether `staticmethod` read as
a value should compare equal to itself across two reads; and no census of the
read-as-a-value spelling in real code -- lekkerzeilen CALLS `gl.get_string(...)`
and does not read it, which is why the call path landed alone.

## See also

- `bug-n-a-staticmethod-or-classmethod-is-unreachable-through-a-class-held-as-a-value`
  -- the parent; the CALL path, resolved 2026-09-13. Its registry diagnosis is the
  one that applies HERE and not there.
- `bug-n-a-class-level-method-through-a-class-value-is-refused-when-the-name-has-two-carriers`
  -- the other residual, on the call side.
- `bug-n-getattr-with-a-literal-method-name-on-a-builtin-container-or-str-is-refused`
  -- the same `hasattr`/`getattr` pair, on a builtin receiver instead of a class.

---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`self.kind` inside a method DECLARED ON THE BASE reads the base's class attribute even for a Derived instance — `Derived(3).describe()` says 'base:3' where CPython says 'derived:3'. `d.kind` and `Derived.kind` are both correct, so only the read through `self` in an inherited method is wrong. The template-method pattern (a base method reading a subclass's constant) silently uses the wrong constant"
status: done
owner: claude-AN
---

# `self.<class attribute>` in an INHERITED method reads the base's value

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-13, differential sweep against CPython.
- **Pre-existing:** identical on `stable_linux_amd64/default/pinned`.

```python
class Base:
    kind = "base"
    def __init__(self, n):
        self.n = n
    def describe(self):
        return self.kind + ":" + str(self.n)

class Derived(Base):
    kind = "derived"

d = Derived(3)
print(d.describe(), d.kind, Derived.kind)
# pxx      base:3 derived derived
# CPython  derived:3 derived derived
```

## The boundary

| read | pxx | CPython |
| --- | --- | --- |
| `d.kind` (through the instance) | `derived` | `derived` |
| `Derived.kind` (through the class name) | `derived` | `derived` |
| `self.kind` inside a method DECLARED ON Derived | (works) | works |
| **`self.kind` inside a method declared on BASE** | **`base`** | `derived` |

Only the inherited-method read is wrong, and it is the one the
template-method pattern is built on: a base method that reads a constant each
subclass redefines (`kind`, `name`, `table`, `sep`). Every subclass then behaves
like the base, silently — no error, and the value is a perfectly good string.

## Where to look

A class attribute is a hidden GLOBAL per (declaring class, name)
([[project_nilpy_class_attributes_are_hidden_globals_not_rtti]]), and inside a
method body `self.kind` resolves through the class-variable-through-an-instance
branch — which is keyed on the class that DECLARES the method (`CurSelfClass`),
not on the receiver's runtime class. `FindClassVar` walks the PARENT chain from
there, so from `Base.describe` it finds Base's slot and stops; the derived
class's own slot, allocated by the same mechanism, is never consulted.

The runtime already has what a correct read needs, as of
[[bug-nilpy-class-attribute-through-a-class-reference-reads-garbage]] (2026-08-13):
every class attribute is now published into a registry keyed on the class RTTI
blob with its slot ADDRESS, and `PyClsAttrSlotOf` walks `ParentRTTI` from the
RECEIVER's class. So the fix is available without new metadata: when the
attribute is redeclared anywhere in the chain below the declaring class, the
read through `self` has to go through the receiver's class at RUN time instead
of resolving to the declaring class's slot at compile time.

Cheaper alternative worth measuring first: `PyClsAttrRedeclaredInChain` already
detects exactly this shape (it forces the shared-slot lowering when a subclass
redeclares an attribute) — so the machinery to spot the case exists, and what is
missing is making the `self.` read dynamic when it fires.

## Gate

A `.npy` diffed against CPython: a base method reading a redeclared attribute
through `self`, a two-level chain (`A` → `B` → `C` each redefining it), a
subclass that does NOT redefine it (must still see the base's), the same
attribute read through the instance and the class name as controls, a
`super().describe()` call, and an attribute written on the class after
construction.

## 2026-08-13 — FIXED, using the registry the class-ref work had just landed

`FindClassVar` walks UPWARD from the class that declares the METHOD, so inside
`Base.describe` it found Base's slot and stopped — the subclass's own slot,
allocated by the same mechanism, was never reachable from there. Which slot is
right is a fact about the RECEIVER, so the read is now one at run time whenever
the attribute is redeclared down the chain:

  * `PyClsAttrRedeclaredCi(ci, name)` asks the CLASSVAR table (not a token
    re-scan like the pre-pass's `PyClsAttrRedeclaredInChain`, which runs before
    that table exists) whether two classes in one line of descent declare the
    name;
  * `pyclsattr_inst_get(obj, name)` reads it off the instance's own class,
    walking `ParentRTTI` — the same walk `Derived.kind` does, which is why THAT
    spelling was always right. It reuses `PyClsAttrSlotOf` and the bind registry
    landed earlier today for
    [[bug-nilpy-class-attribute-through-a-class-reference-reads-garbage]], so
    this needed no new metadata;
  * the static resolution is kept for every attribute NOT redeclared (no cost
    where there is no ambiguity), for assignments and augmented assignments, and
    for Pascal, which keeps the class-var semantics FPC gives it.

A bare `kind` inside a method is deliberately NOT touched: in Python that is a
global lookup, not the class attribute.

### Gate

`test/test_nilpy_inherited_class_attribute_through_self.npy` + `.expected` from
CPython, wired into `make test-nilpy`: a base method reading a redeclared
attribute, a THREE-level chain each redefining it, a subclass that does not
redefine it (must see the base's), a second attribute redefined only two levels
down, `super().get()`, the `sep.join` shape this pattern is usually written as,
and the instance/class-name reads as controls. `make test-nilpy` green,
`gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit c6530b249.

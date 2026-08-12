---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`c = A` then `c.num` answers 24 where CPython answers 7 and `c.name` answers the empty string: a class attribute read through any class REFERENCE (alias, parameter, dict or list element) is garbage, while the literal `A.num` is correct. The WRITE side is lost too — `c.num = 9` leaves A.num at 7. The plugin-registry shape: register(cls), then registry[k].name"
---

# A class attribute read through a class REFERENCE reads garbage

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython — a plugin
  registry (`register(cls)` keyed on `cls.name`), which is the canonical use of
  a class as a value.
- **Sibling:** [[bug-nilpy-class-attribute-unreachable-through-the-class-name]]
  (done) made the LITERAL `A.attr` work. This is the same read one step of
  indirection later, and it is silent where that one was loud.

```python
class A:
    name = "a"
    num = 7

def f(cls):
    return cls.name

c = A
d = {"k": A}
lst = [A]
```

| read | pxx | CPython |
| --- | --- | --- |
| `A.name` / `A.num` (the literal class) | `'a'` / `7` | same |
| `c.name` / `c.num` (an ALIAS) | **`''`** / **`24`** | `'a'` / `7` |
| `f(A)` — through a parameter | **`''`** | `'a'` |
| `d["k"].name` | **`''`** | `'a'` |
| `lst[0].name` | **`''`** | `'a'` |
| `A().name` (through an INSTANCE) | `'a'` | `'a'` |

`c.num` answering **24** is the one that matters: a plausible integer, no
error, no warning. The string reads answer empty, which is the same failure
mode one type over. The instance read and the literal read are both fine, so
the attribute exists and is stored correctly — it is reading it off a class
HANDLE that goes wrong.

In a full registry program the failure surfaces earlier and louder:
`AttributeError: 'type' object has no attribute 'name'` when the class comes
back out of a dict, which is what a plugin/handler table does on every lookup.

## Where to look

A class held as a value is a `VT_CLASSREF` variant
([[project_nilpy_callable_has_three_representations]] is the same family of
hazard: several representations for one concept, and crossing them writes one
kind's payload into another kind's slot). The literal `A.attr` is resolved by
the frontend against the class's own attribute table; the reference form has
to go through the RTTI the class-as-a-value work already reflects for
construction (`PyClassRefNew`). Expect the attribute read to be falling through
to an INSTANCE field read on a handle that is a class-ref, i.e. reading at the
field's offset inside the RTTI blob — which is exactly the shape of a 24 where
7 was stored.

**The write side is wrong too, and measured:**

```python
class A:
    num = 7
c = A
c.num = 9
print(A.num, c.num)     # pxx: 7 9      CPython: 9 9
print(A().num)          # pxx: 7        CPython: 9
```

So `c.num = 9` does NOT write the class attribute — it lands somewhere the
alias reads back and the class does not, which is why the read through the alias
then looks self-consistent. A registry that sets a default on a registered
class (`cls.enabled = False`) therefore silently changes nothing that any
instance or the class itself will see. Whatever slot it does write has to be
identified as part of this: if it is inside the RTTI blob, that is memory
corruption, not just a lost write.

`getattr(cls, "name")` is worth a row too — it is the other spelling of the
same read.

## Gate

A `.npy` diffed against CPython: every row of the table above for a str, an
int and a float attribute; a class reference passed through two calls; a
registry dict keyed by `cls.name` (the shape that found this); an inherited
class attribute read through a reference to the SUBCLASS; the write side; and
`A.attr` / `A().attr` kept in the same file as the controls.

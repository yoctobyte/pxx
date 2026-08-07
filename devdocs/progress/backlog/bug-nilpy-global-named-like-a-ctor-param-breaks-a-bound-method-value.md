---
track: N
prio: 40
type: bug
summary: "A bound-method VALUE taken off a global whose name matches another class's ctor parameter raises AttributeError — `gb = b.hit` fails while `g = k.hit` on the same class succeeds in the same file. Name-dependent, so any test that happens to pick a colliding name reports the wrong bug"
---

# A global named like another class's ctor parameter breaks a bound-method value

```python
class C:
    def __init__(self, b):        # <-- parameter named b, stored as self.b
        self.b = b
    def m(self, x):
        return self.b + x

class Counter:
    def __init__(self):
        self.hits = 0
    def hit(self, n):
        self.hits = self.hits + n
        return self.hits

b = Counter()                     # <-- global named b
gb = b.hit                        # bound-method VALUE
print("b", gb(3))
```

```
Unhandled exception: AttributeError: 'Counter' object has no attribute 'hit'
```

CPython prints `b 3`. Rename the global to anything that does not collide and it
works. In the same file, `k = Counter(); g = k.hit; g(1)` succeeds — so the
class, the method and the value form are all fine; only the NAME differs.

Repro kept at `/tmp/coll_repro.npy` in the session that filed this; it is 16
lines and reproduces above verbatim.

## Pre-existing

Identical on `stable_linux_amd64/default/pinned`, so this is not new. Found
while fixing [[bug-nilpy-bound-method-of-a-temporary-receiver-segfaults]],
whose test happened to use `a` and `b` as instance names and so reported this
bug instead of its own.

## Narrowing already done — each ingredient ALONE is insufficient

Measured, all answering correctly:

| shape | result |
| --- | --- |
| class with a FIELD `self.b` (param named `q`) + global `b` | correct |
| class with a PARAM `b` (field named `z`) + global `b` | correct |
| param and field BOTH named `b`, global `b`, **direct call** `b.hit(3)` | correct |
| param and field both `b`, global `b`, **value form** `gb = b.hit` | correct (!) |
| all of the above **plus** `C` having a method that reads `self.b`, and `Counter` having an `__init__` | **FAILS** |

So the minimal repro is not the obvious one: the collision alone does nothing,
and the bound-method value alone does nothing. The last row is where it tips,
which points at the pre-pass that types globals rather than at the value form
itself — but the exact ingredient was not isolated, and the four passing rows
above are the useful part of that hunt, not a conclusion.

## Related, probably the same family

[[project_nilpy_name_matching_a_class_is_typed_as_that_class]] — a param/local/
field named like a CLASS was typed AS that class, fixed with a case-sensitive
value-position lookup. This is the mirror: a GLOBAL named like a class's
member/param. Whatever types module-level names in the pre-pass is the place to
look, and the lesson from that fix applies directly: **when narrowing, vary the
NAMES as a dimension** — a test whose variables happen to collide reports
somebody else's bug.

## Gate

Per-fix loop, plus a `.npy` test that deliberately uses colliding names across
a global, a ctor parameter and a field, diffed against CPython.

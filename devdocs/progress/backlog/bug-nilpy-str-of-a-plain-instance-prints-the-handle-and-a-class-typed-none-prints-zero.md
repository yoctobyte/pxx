---
track: N
prio: 52
type: bug
blocked-by: [bug-nilpy-a-def-returning-a-field-is-typed-as-the-receivers-class]
summary: "`str(obj)` on a class that declares no __str__/__repr__ prints the raw handle (134298980057) where CPython prints `<__main__.N object at 0x…>` — while repr(obj) and print([obj]) are both right. And a CLASS-TYPED None — what a method with `return self` on one path and `return None` on another yields — prints as 0, though `is None` on it answers True"
---

# `str()` of a plain instance prints the handle; a class-typed `None` prints 0

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-12, differential bug hunting — a tree's `find()` returning
  None for a missing name, which is as ordinary as a lookup gets.

Two symptoms, one cause: the frontend's class arm for `str`/`print` falls
through to the INTEGER path when the class declares no `__str__`/`__repr__`,
and a class-typed nil handle is just another integer to it.

## Symptom 1 — `str(instance)` is a number

```python
class N:
    def __init__(self):
        self.v = 1

n = N()
print(str(n))      # pxx: 134298980057    CPython: <__main__.N object at 0x...>
print(repr(n))     # both: <__main__.N object at 0x...>   -- correct
print([n])         # both: [<__main__.N object at 0x...>] -- correct
```

`repr()` and the container render go through `pyvar_repr` (which knows the
CPython shape); `str()` does not.

## Symptom 2 — a class-typed `None` prints 0

```python
class N:
    def __init__(self, name):
        self.name = name
        self.kids = []

    def find(self, nm):
        if self.name == nm:
            return self
        for k in self.kids:
            r = k.find(nm)
            if r is not None:
                return r
        return None

r = N("a")
print(r.find("zz"))            # pxx: 0        CPython: None
print(r.find("zz") is None)    # both: True
x = r.find("zz")
print(x, x is None)            # pxx: 0 True   CPython: None True
```

`is None` is RIGHT, so the value is a recognised None — only its rendering is
wrong. The method's return type is the class (from `return self`), so the nil
handle is printed as the integer it is.

The same shape through a top-level `def` prints `None` correctly, because that
def's return type infers to a variant and the variant renderer handles nil. So
this is the class-typed arm specifically, and it is the arm a METHOD takes.

## Where to look — and do all of it at once

`PyReprContainer` (pyparser.inc) handles a `tyClass` node by trying
`PyClassStrNode` (a user `__str__`/`__repr__`), then the pylib containers, and
then **Exits unchanged** — leaving an integer print of the handle. The `str()`
site in parser.inc has its own copy of that decision.

The fix is to box a class-typed value into a variant and let `pyvar_print_of` /
`pyvar_repr` render it — they already produce CPython's `<__main__.X object at
0x…>` and already answer `None` for an empty tag; symptom 2 then needs the nil
handle to box as VT_EMPTY rather than a VT_OBJECT with a nil payload.

**Do not fix one site only.** Value-to-text has three frontend sites plus repr
([[project_nilpy_three_rendering_paths_print_str_fstring]]), and this ticket is
already two of them disagreeing.

## 2026-08-12 — implemented, GREEN on its own test, and REVERTED. Read this first.

The fix works and is the right one: `pyobj_str_of` in pylib (nil -> 'None',
otherwise box + `pyvar_print_of`), wired into `PyReprContainer`'s class tail and
into the f-string/`pystr_of` class arm in parser.inc, plus a nil check in
`repr(TObject)`. All three rendering paths then matched CPython exactly —
`str`, `repr`, `print`, a container, `"%s"` and an f-string, for a class with no
dunders, with `__str__` only, with `__repr__` only, with both, and for a
class-typed None.

**It was reverted because `make test-nilpy` went RED with a SEGFAULT**, and the
cause is not in the fix:
[[bug-nilpy-a-def-returning-a-field-is-typed-as-the-receivers-class]]. A def
whose body is `return q.n` is typed `tyClass` while the value it returns is the
field's int; today that prints correctly only because the wrong type renders
through the integer path and the value IS an integer. The moment a `tyClass`
node is treated as an object — which is precisely what this fix does — the
renderer dereferences 5 as a pointer.

So this ticket is **blocked on the typing bug**, not on any difficulty of its
own. Fix that first, then re-apply this; the implementation above is a
half-hour of work once the types are honest.

## Gate

A `.npy` diffed against CPython: `str`/`repr`/`print`/f-string/`"%s"` of an
instance with no dunders, with `__str__` only, with `__repr__` only, and with
both; a class-typed None from a method printed through each of those; the same
None from a top-level def (the row that already works); and `is None` asserted
alongside each so a rendering fix cannot quietly change the semantics.

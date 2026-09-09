---
slug: bug-n-a-local-bound-to-both-a-pascal-class-and-its-subclass-loses-subscripting
track: N
prio: 30
type: bug
status: backlog
owner: ""
created: 2026-09-09
found-by: frankB
tags: [nilpy, subclass, default-property, rebinding]
blocked-by: []
summary: "A name bound at one site to a Pascal class and at another to a NilPy SUBCLASS of it aborts at run time with `TypeError: object is not subscriptable` on the subscript, where CPython works. Measured 2026-09-09: `g = array.array(\"h\", bytes(2)); print(g[0]); g = Grid(\"h\")` with `class Grid(array.array)` fails at the FIRST subscript -- the one compiled before the subclass binding exists -- so it is the name's resolved TYPE that is wrong, not the operation. Three controls narrow it: the same name bound twice to the SAME Pascal class works; a Grid instance subscripted with no second binding works; and pure NilPy classes with __getitem__ rebound base->subclass work. So it is specific to a PASCAL class's `default` indexed property plus two bindings whose classes are related by inheritance. Loud, not silent."
---

# A local bound to both a Pascal class and its subclass loses subscripting

## Measured 2026-09-09 (compiler 14e1b089f0c9)

```python
import array
class Grid(array.array):
    pass

g = array.array("h", bytes(2))
print(g[0])          # CPython: 0   NilPy: TypeError: object is not subscriptable
g = Grid("h")
```

**The failing subscript is the one written BEFORE the subclass binding**, which
is what says this is about the name's resolved type rather than about the
subscript or about the subclass instance.

## Controls, which is what narrows it

| case | result |
| --- | --- |
| same name bound twice to the SAME Pascal class (`array.array("d")` then `array.array("h")`) | works, matches CPython |
| a `Grid` instance subscripted, ONE binding only | works |
| pure NilPy classes with `__getitem__`, rebound base -> subclass | works, matches CPython |
| Pascal class + subclass, two bindings | **aborts** |

So: not rebinding in general (`test_nilpy_rebind_across_unrelated_classes`
covers the unrelated case and passes), not subclassing in general, not the
default property in general. It needs all three — a Pascal `default` indexed
property, a NilPy subclass of that Pascal class, and two bindings of one name
whose classes are related by inheritance.

## Why it is prio 30

It is LOUD — an unhandled TypeError at run time, naming the operation. Nothing
in the corpora does this; it was found by writing a test that reused a variable
name, and the reuse was the test's own sloppiness. It is filed because the
measurement is real and the narrowing is already done, not because anything is
blocked on it.

Adjacent and probably the same machinery: the module-global binding resolver
collapsed on 2026-09-09 (`PyModuleBindingsOf`) deliberately returns EVERY
binding site rather than the first, because the three callers disagree about a
name rebound at module scope. This is the LOCAL twin of that question and the
answer here is currently "one binding decides every site".

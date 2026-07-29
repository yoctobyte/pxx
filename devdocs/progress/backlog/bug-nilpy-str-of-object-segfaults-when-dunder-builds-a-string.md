---
track: N
prio: 75
type: bug
---

# `str(obj)` SEGFAULTS when `__str__`/`__repr__` builds a string and nothing touched the instance first

```python
class V:
    def __init__(self, v: int):
        self.v = v
    def __str__(self) -> str:
        return "A(" + str(self.v) + ")"

a = V(1)
print(str(a))          # CPython: A(1)     pxx: SIGSEGV
```

Seven lines. `__repr__` in place of `__str__` behaves identically.

## What it is NOT — two wrong leads, both measured out

The first reading was "`__repr__` is unimplemented". It is implemented:
PyStrOfValue falls back to `__repr__` when `__str__` is absent, and a
`__repr__` returning a LITERAL prints correctly. The second reading was
"`str(self.v)` inside the dunder recurses". It does not — the gdb backtrace is
two frames deep, and replacing `str(self.v)` with a local (`n = self.v; ...
str(n)`) crashes identically.

## What it actually depends on

| program | result |
| --- | --- |
| `__str__` returns a LITERAL (`return "S"`) | works |
| `__str__` returns a CONCATENATION | **SIGSEGV** |
| same body, method named `show()`, called as `a.show()` | works |
| `print(a.v)` on the line BEFORE `print(str(a))` | **works** |
| a class with more methods around it (`get`, `__eq__`) | works |

So it needs all of: dispatch through `str(obj)` (not a direct method call), a
managed — i.e. built, not literal — result, and no earlier statement touching
the instance. Crash is inside `V.__str__ + 0x50` itself, per the `.map`.

## The IR says it plainly — a field typed as a CLASS

`PXXDBG=a.ir:V.__str__` on the crashing program:

```
0: zero_sym  a=264                       tk=23    <- $pyresult IS zero-initialised
1: const_str a=37 b=1                    tk=4
2: load_sym  a=263 [sym=self]            tk=6
3: field     a=2 ival=8 [offset=8]       tk=6     <- self.v typed tyClass (6), not int
4: load_mem  a=3                         tk=6
5: arg       a=4                         tk=6
6: call      a=945 b=5                   tk=23    <- the OBJECT str path
7: binop     a=1 b=6 c=70                tk=23
8: store_sym a=264 b=7 [sym=$pyresult]   tk=23
```

`self.v` is `int`, assigned from an annotated `__init__` parameter, and inside
`__str__` it carries tk=6 — tyClass. So `str(self.v)` takes the object route
and dispatches `__str__` on the integer 1 as if it were an instance, which is
why the crash is inside `V.__str__` itself, one frame below the outer call, and
why the backtrace is short rather than a recursion blowup.

The two programs differ ONLY in the extra `print(a.v)` line, and the same IR
node differs with them:

```
crashing : 3: field a=2 ival=8 [offset=8]  tk=6    (tyClass)
working  : 3: field a=2 ival=8 [offset=8]  tk=13   (tyInt64)
```

That also explains the "fix" of touching the instance first: `print(a.v)` on an
earlier line resolves the field's type before this method is lowered. It is the
class-pipeline ordering hazard — names early, members late
([[project_nilpy_class_pipeline_ordering]]) — with tyClass as the silent
default for a field whose type is not yet known.

(The earlier reading in this ticket — an uninitialised managed Result slot —
was WRONG: `$pyresult` is zero-initialised right there at IR 0. Recorded
because the wrong theory was plausible and cost a round; the IR settled it in
one command.)

So the fix is about field-type resolution order, not about ARC. It may still
share a root with [[bug-nilpy-method-returning-a-fresh-string-leaks]], but that
now looks like a separate defect rather than the same one.

Found by the OOP sweep against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus `str()`/`print()`/`format()`
of an object whose `__str__` and/or `__repr__` builds a string, as the FIRST
statement touching the instance.

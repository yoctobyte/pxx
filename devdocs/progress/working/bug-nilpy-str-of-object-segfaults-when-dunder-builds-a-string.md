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

## RESOLVED — the CLASS NAME was the trigger, not `__str__`

The final narrowing: rename the class and the crash goes away.

```
class A    field v        -> works
class V    field v        -> SIGSEGV
class Node field node     -> SIGSEGV
class Node field other    -> works
```

A field whose name matches a CLASS name — its own or any other, matched
case-insensitively under Pascal rules — was registered as an instance of that
class. In the class-member pre-pass (pyparser.inc), the right-hand side of
`self.node = node` went to `PyTypeFromTokenIndex` first, whose `tkIdent` arm
ends with `else if IsClassType(...) then Result := tyClass`. The parameter
lookup that would have said "int" ran only if that returned tyUnknown, so the
class hit preempted it.

The field was then tyClass, `str(self.node)` took the OBJECT route, and
`__str__` was dispatched on the integer 1 as if it were an instance.

The fix is order, not logic: for a bare identifier right-hand side, ask
`PyHeaderParamType` (is this a parameter of the enclosing method?) BEFORE the
type scanners. A parameter name is a value and must win. Anything that is not a
parameter falls through to exactly the scanners it used before.

Verified still correct afterwards: a genuinely class-typed field from an
annotated parameter (`def __init__(self, inner: Inner): self.inner = inner`)
and one from a construction (`self.made = Inner(9)`) both keep their class
identity, with method calls through both.

### Why the earlier readings were wrong, in order

1. "`__repr__` is unimplemented" — it is implemented; `__str__` crashed too.
2. "`str(self.v)` recurses" — the backtrace is two frames.
3. "the managed Result slot is uninitialised" — `zero_sym` is IR node 0.

Each was plausible and each cost a round. What actually settled it was
`PXXDBG=a.ir` on the crashing and the working program and diffing the two: one
node differed, `field ... tk=6` against `field ... tk=13`. Measure, do not
reason.

### Gate

`tools/gate.sh full`.

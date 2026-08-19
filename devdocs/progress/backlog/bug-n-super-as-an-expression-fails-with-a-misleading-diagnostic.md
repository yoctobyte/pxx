---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`return super().hi()` (super() in expression position, documented as unsupported) is refused with `error: Nil Python: annotate the type / too dynamic [a=22 b=8]` reported at line 1 — a diagnostic that names neither the construct nor the right line. Also: `B.__init__(self)` for a second base is `class method not found`."
---

# `super()` in expression position: the refusal is right, the diagnostic is not

- **Type:** bug (Track N) — filed by Track D from
  [[docs-verify-nil-python-page-against-the-compiler]].
- **Found:** 2026-08-19 against pin **v363**. Low priority: the limitation is
  documented and has a working spelling; it is the *diagnostic* that costs time.

## Repro

```python
class P1:
    def hi(self) -> str:
        return "P"
class C1(P1):
    def hi(self) -> str:
        return "C"
    def viasuper(self) -> str:
        return super().hi()
print(C1().viasuper())
```

```
pascal26:1: error: Nil Python: annotate the type / too dynamic [a=22 b=8]
  near: >>>  P1
```

Line 1 is `class P1:`; the offending construct is on line 8. The message asks
for an annotation, which cannot fix it, and prints raw node numbers. The
supported form — `Parent.method(self)` — compiles and returns `P` correctly, so
the fix is a diagnostic that says "super() is a statement form; write
`P1.hi(self)`" at the real line.

## Second, related finding

With multiple bases, calling the second base's initialiser explicitly is
refused:

```python
class C(A, B):
    def __init__(self) -> None:
        A.__init__(self)
        B.__init__(self)   # pascal26:10: error: class method not found: __init__
```

CPython runs this and sets both fields. Multiple bases otherwise work on v363
(methods from both are callable; first base wins on a name clash), so this is
the one hole in them — it is what stops a two-base class from chaining both
constructors.

## Log
- 2026-08-19 — filed from a Track D documentation verification pass.

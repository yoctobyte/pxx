---
track: N
prio: 80
type: bug
---

# NilPy identifiers are case-INSENSITIVE; Python's are case-sensitive

- **Type:** bug (NilPy semantics — SILENT WRONG VALUE, fundamental) —
  **Track N**
- **Found:** 2026-08-02, while reducing
  [[bug-nilpy-parent-method-call-breaks-if-parent-instantiated-first]], which
  turns out to be one symptom of this.

## Measured

```python
x = 1
X = 2
print(x, X)          # CPython: 1 2     pxx: 2 2
```

Two distinct Python names are one variable in pxx. Silent, and it corrupts a
value rather than failing.

The symptom that led here is the same cause wearing a disguise:

```python
class A:
    def call(self):
        return "A"
a = A()                              # `a` and `A` become the SAME name
class E(A):
    def call(self):
        return "E:" + A.call(self)   # error: unexpected token
```

Renaming the variable to `zz` makes that compile and print `E:A`. So the class
`A` was being shadowed by the instance `a`.

## Why it is this way, and why NilPy is different

Case-insensitive resolution is deliberate and correct for the PASCAL frontend —
it is FPC parity, and `bug-case-insensitive-incomplete-builtins-funcs` (done,
2026-06-23) exists specifically to make it MORE thorough: unqualified
`MatchProcCall` and builtins were made case-insensitive on purpose.

Python is case-sensitive. So the shared resolution layer is right for one
frontend and wrong for the other, and NilPy currently inherits Pascal's rule.
This is the same shape as the C frontend's
`project_c_struct_fields_case_sensitive_b231` — C is case-sensitive too, and
that needed a per-frontend answer.

## Scope measured so far

| case | result |
| --- | --- |
| `x = 1; X = 2` | **merged** — `print(x, X)` gives `2 2` |
| `class Foo` + variable `foo`, constructing `Foo()` | works |
| `class Foo` + variable `foo`, reading `foo` | works |
| `def go` + variable `GO` | works |
| **`class A` + variable `a`, then `A.method(self)`** | **compile error** |

So it does not break everything — it breaks where two differently-cased names
must be told apart, and the failure ranges from a wrong value to a confusing
parse error.

## Fix shape — needs a decision, not just code

The resolution layer is SHARED. Making it case-sensitive wholesale would break
the Pascal frontend's FPC parity, which is a deliberate, tested behaviour. The
options are:

1. **A per-frontend flag on the lookup** — `NilPyUserCode` already exists as a
   predicate and gates other NilPy-only rules; resolution would consult it.
   Most surgical, but every lookup site has to honour it or the split leaks.
2. **Case-fold at name INTERNING time per frontend** — Pascal folds, NilPy does
   not. Fewer sites, but changes what is stored, so it touches the symbol table
   and anything comparing interned ids.
3. **Leave it and document** — untenable: `x` and `X` silently aliasing is a
   correctness bug, not a dialect choice.

This is a Track U-shaped call about how far the frontends' name rules diverge,
and it is expensive to get wrong. Recommend option 1, gated behind the full
suite for BOTH frontends, and staged: make the lookup honour the flag, prove
Pascal is byte-identical, then flip NilPy.

## Gate

A `.npy` diffed against CPython covering two variables differing only in case,
a class and an instance differing only in case (the repro above), a function and
a variable, attribute names differing only in case on one object, and a keyword
argument matching a parameter with different case. Plus `make test` and the
Pascal corpus byte-identical, since the shared layer is being touched.

## 2026-08-02 — this bug caused a WRONG ROOT CAUSE to be recorded elsewhere

Add to the blast radius: it produced a misdiagnosis that got a separate fix
reverted and a wrong conclusion written into a ticket, where it sat until
someone re-measured.

On [[bug-nilpy-class-attribute-unreachable-through-the-class-name]], the
class-attribute lookup fallback was reverted because this program "silently"
gave 0 instead of 1:

```python
class A:
    n = 0 + 0
    def __init__(self):
        A.n += 1
a = A()
print(A.n)
```

That was read as an unexplained interaction between the hoisted `$clsattr`
initialiser and the constructor. It is not. **`a` and `A` are the same
identifier**, so `a = A()` rebinds the class name to the instance and `A.n`
then reads the instance's stale copy. Renaming the variable to `zzz` gives the
correct answer with no code change. Reduced to a one-liner with no constructor:

```python
class A:
    n = 0 + 0
a = 5
print(A.n)        # prints 5
```

The instructive part is the SHAPE of the confusion: single-letter locals paired
with a capitalised class (`a = A()`, `p = P()`, `c = Counter()`) are the single
most common spelling in Python, so this bug hides *inside the most idiomatic
code in the language* and reads as "the feature I just wrote is broken".

A second sighting the same day: `class Counter` fails to compile entirely
("no such member on this record/class") — `Counter` collides
case-insensitively with something already in scope, presumably pylib's
`TPyCounter` family. `class Reg` with identical code compiles fine.

**Implication for prioritisation:** the cost of this bug is not only the
programs it breaks, it is the debugging time it silently misdirects and the
false conclusions it plants in other tickets. That is an argument for the
existing prio 80, not against it.

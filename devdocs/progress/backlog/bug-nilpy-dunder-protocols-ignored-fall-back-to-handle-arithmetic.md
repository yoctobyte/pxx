---
track: N
prio: 60
type: bug
---

# User-defined dunders are ignored, and the operator then does arithmetic on the object HANDLE

```python
class C:
    def __init__(self):
        self.d = [1, 2, 3]
    def __len__(self):
        return len(self.d)
print(len(C()))          # CPython: 3       pxx: 1436549184
```

The method is parsed, registered and simply never consulted; the builtin falls
through to its generic path, which reads the instance pointer as a number. Same
failure shape as
[[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]] (now fixed for
the scalar operand pairs): a different plausible value on every run, no
diagnostic.

## Measured — which protocols work and which are silently wrong

| dunder | reached? | pxx | CPython |
| --- | --- | --- | --- |
| `__init__` | yes | — | — |
| `__str__` | yes | correct | correct |
| `__bool__` | yes | correct | correct |
| `__eq__` | yes | correct | correct |
| **`__len__`** | **no** | `1436549184` | `3` |
| **`__contains__`** | **no** | `False False` | `True False` |
| **`__call__`** | **no** | `124295816675384` | `2` |
| **`__add__`** | **no** | `268329319137376` | `3` |
| `__lt__` (via `sorted`) | no | `TypeError: expected a number, got object` | `1` |
| `__getitem__` | no | compile error (does not parse) | `8` |
| `__repr__` | n/a | `repr` builtin missing | `R` |
| `__iter__` | n/a | `iter` builtin missing | `[1, 2]` |

The four in bold are the dangerous ones — a wrong VALUE with no error. `__lt__`
now raises rather than answering off an address, but only as a side effect of
the pycmp_v fix, not because the dunder is dispatched.

## Why `__add__` still slips through the operand-clash work

`IRPyNumStrClash` deliberately only reports a str-vs-number pair, and `pyadd_v`
is only reached when an operand is a VARIANT. `C(1) + C(2)` is two statically
`tyClass` operands, so it takes the raw `IR_BINOP` path and adds the handles.
Extending the clash predicate to class operands is NOT a safe blanket fix:
`Path("a") / "b"` is pathlib's join and is routed specially, and a class operand
is exactly what an `__add__` would make legal. So the operand question and the
dunder question have to be answered together — which is why this is one ticket
rather than an addendum to that one.

## Suggested order

1. **`__len__` and `__contains__`.** DONE (commit 3a3204d876d3f07fe94a2727713d79074d36ba58). Both are dispatched to the
   user method when the resolved receiver is a non-pylib class; a class with
   NEITHER dunder now raises a genuine runtime TypeError (a new
   `PyNotContainerError`/the existing `pylen_v` Variant fallback) instead of
   silently reading garbage. One real wrinkle found along the way: the
   `len()` case's first attempt REWOUND unconditionally for the no-`__len__`
   shape and depended on which OTHER classes happened to exist elsewhere in
   the file for whether it raised or read garbage — confirmed with
   `PXXDBG=a.ir` that the compiler's overload matcher silently picks the
   TPyList overload for ANY unmatched tyClass argument, not just the one
   with `__len__`. Fixed by never rewinding for a non-pylib-container class,
   dunder present or not. Regression: `test/test_nilpy_dunder_len_contains.npy`.
2. **`__call__`.** DONE (commit 1536e5901e50d992011c302d8ae722346269c1ac). `a(x)` dispatches to `__call__` via a new
   `PyMakeCallDunder`, arbitrary arity, looped so a returned callable composes.
   No `__call__` raises `PyNotCallableError` (a genuine runtime TypeError)
   rather than the pre-existing hard parse error. Regression:
   `test/test_nilpy_dunder_call.npy`.
3. **`__getitem__` / `__setitem__`.** STILL OPEN. `C()[1]` no longer fails
   to parse (that changed since this ticket was opened) but now silently
   returns a WRONG value (`0` instead of the real element) — `b[1]` on an
   ident-based class value routes through the SHARED `ParseLValueAST`
   (parser.inc), not the expression-postfix chain `__len__`/`__contains__`/
   `__call__` were fixed in. That function is large, shared with every OTHER
   frontend's lvalue parsing, and historically fragile — a different ticket
   this same session (bug-nilpy-chained-subscript-assignment-writes-only-
   the-last-target) explicitly backed away from editing it blind. Needs a
   dedicated pass: find where it falls through to Pascal's default-indexed-
   property machinery for a tyClass base with no default property declared,
   and add the same "resolve FindUMeth('__getitem__'/'__setitem__') on a
   non-pylib class" check the three landed dunders use, on BOTH the read and
   the write (`x[i] = v`) sides.
4. **Arithmetic and ordering dunders** (`__add__`, `__lt__`, …), together with
   the class-operand question above. Largest, and the one that wants a Track U
   decision about how far NilPy follows Python's operator protocol. STILL OPEN.

Until each is dispatched, the corresponding operator should say so rather than
compute off a handle — the mixed-type work's rule (warn where provable, raise at
run time) applies unchanged here.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` per protocol with
CPython's own output as the expectation.

## Related loud gaps found in the same sweep

Compile errors, not wrong values, so they are feature gaps rather than bugs —
recorded here so the OO surface is described in one place:
`@staticmethod` / `@classmethod` inside a class, class-level variables
(`class K: n = 0`), multiple inheritance, a class body that is just `pass`
(`class MyErr(Exception): pass` — the standard custom-exception spelling),
`try/else`, and the `repr` / `iter` builtins.

## Also measured: a @dataclass gets no generated `__eq__`

```python
from dataclasses import dataclass
@dataclass
class P:
    x: int
print(P(1) == P(1))     # CPython: True     pxx: False
```

CPython's `@dataclass` generates `__eq__` comparing the fields; pxx compares by
identity, so two structurally equal dataclasses are unequal. Same root as the
`__eq__` row in the table above (a hand-written `__eq__` IS honoured — it is the
GENERATED one that is missing), so it belongs with this ticket rather than on
its own. Worth doing with `__eq__` since dataclasses are the shape most likely
to be compared by value.

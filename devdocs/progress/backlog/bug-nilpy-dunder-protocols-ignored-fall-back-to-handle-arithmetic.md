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

1. **`__len__` and `__contains__`.** Both are already funnelled through a single
   pylib entry point (`pylen_v`, `pycontains`/`pydictcontains`) that dispatches
   on the tag, and tag 7 already branches on `is TPyList` / `is TPyDict`. Adding
   "otherwise, if the class defines the method, call it" is a contained change
   at one site each, and it covers the two commonest protocols.
2. **`__call__`.** `obj(x)` currently produces the handle. The dynamic-call
   machinery for a callable value already exists (`pyvar_callv*`); this is
   routing an instance with a `__call__` into it.
3. **`__getitem__` / `__setitem__`.** Needs the parse gap closed first —
   `C()[1]` does not currently parse at all.
4. **Arithmetic and ordering dunders** (`__add__`, `__lt__`, …), together with
   the class-operand question above. Largest, and the one that wants a Track U
   decision about how far NilPy follows Python's operator protocol.

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

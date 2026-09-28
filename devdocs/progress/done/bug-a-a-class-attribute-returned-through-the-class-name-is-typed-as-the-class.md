---
track: A
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-28, Nil Python corpus differential, hosted xtensa/riscv32 vs x86-64; test_nilpy_user_class_shadows_builtin refused on every 32-bit target)
tags: [nilpy, inference, silently-wrong, cross-target]
summary: "A def returning a class attribute through the class NAME (`return C.k`, or `v = C.k; return v`) had its return type inferred as tyClass, because the inference walk typed the token `C` as the class and never looked at `.k`. On x86-64 that was a silent wrong value: a float printed as its raw bits, a str or list as a pointer, None as 0 (int happened to survive). Every 32-bit target, ESP included, refused the write. PyInferExprType now reads the attribute's own recorded type (the instance field, else the shared class-var slot), and answers tyVariant when neither is recorded or a selector follows. It never answers the class for a value that is not one."
owner: ""
---

# A class attribute returned through the class name is typed as the class

```python
class C:
    k = 2.5
def get():
    return C.k
print(get())     # CPython 2.5; pxx v449 x86-64: 4612811918334230528
```

## The class of bug

The return-type walk (`PyInferExprType`, compiler/pyparser.inc) typed a class
NAME token as tyClass. It had an arm for `Cls.method(...)`, which takes the
method's return type, but `Cls.attr` with no call after it fell through, so
the def's return type was widened over the class token.

Measured on the pinned v449, against CPython, float, str, list, None and int
attributes in five shapes:

| shape                          | v449 x86-64                     |
|--------------------------------|---------------------------------|
| method: `return C.k`           | wrong for float/str/list/None   |
| plain def: `return C.k`        | wrong for float/str/list/None   |
| local: `v = C.k; return v`     | wrong for float/str/list/None   |
| `return self.__class__.k`      | right                           |
| classmethod: `return cls.k`    | right                           |

int was right everywhere, since the class slot and an Int64 share a register.
Every non-x86-64 target refused the program ("write of this type not supported
(hosted)" or "write of this operand not yet supported"), which is why
test_nilpy_user_class_shadows_builtin never built on 32-bit.

## The fix

A new arm beside the `Cls.method(` arm: an exact class name followed by
`.ident` and no `(` takes the attribute's type from the instance field of that
name (the copy-at-construction rows), or else from the class-var slot
(`FindClassVar`, which walks the parent chain). A tyClass answer is kept only
when the recorded type names a user class, and it then sets `PyInferLastCi`.
In every other case, including an unrecorded attribute and `C.k.x`/`C.k[i]`,
the answer is tyVariant.

## Measured (2026-09-28, fixedpoint 164a86a81e50)

- `test/test_nilpy_class_attr_return_type.py` covers the table above, plus an
  inherited attribute, a redeclared attribute, an attribute rebound through
  the class name, bool/dict/tuple, `C.s.upper()`, `C.t[1]`, an instance and a
  class stored as attributes. Its .expected is CPython's output.
  - It matches on x86-64, i386, arm32, hosted riscv32, and hosted xtensa on
    both the windowed and call0 ABIs.
  - Control: the pinned v449 differs on x86-64 and refuses on i386.
- `test_nilpy_user_class_shadows_builtin.npy` now builds and matches its
  .expected on i386, arm32, riscv32 and xtensa windowed. The pin refuses it on
  i386.

## Not fixed here

`return type(self).k` is refused at parse time ("expected newline after
statement"). It is a loud refusal and a separate construct.

---
track: A
prio: 70
type: bug
status: done
---

# NilPy: a 1-character string literal was a char, and segfaulted as an argument

Found 2026-07-20 while testing [[bug-a-nilpy-subclass-overlays-parent-layout]] —
the inheritance repro crashed only because its objects were named `"d"`.

## Repro

```python
class A:
    def __init__(self, n: str) -> None:
        self.n = n

a = A("d")     # SIGSEGV;  A("dd") works
print(a.n)
```

## Cause

The shared factor types any 1-character literal as tyChar (correct for Pascal,
where `'d'` IS a char). Python has no char type, so this made every
string-expecting context depend on a char->string coercion — and the
method/constructor argument paths have none. The character CODE (0x64 for `"d"`)
was passed where the callee dereferenced a string pointer. A plain `def`
argument survived because the frozen-string parameter path normalizes an
AN_INT_LIT/tyChar argument into a string literal; the class paths do not.

## Fix

da66e43d — a 1-character literal stays AN_STR_LIT under `PyExprMode`; the Pascal
dialect's char literal is untouched. `ord()` then needed a string operand path
(the ordinal intrinsic would take the string's pointer for its code): a string
argument routes to pylib's new `pyord_s` as a normal AN_CALL, so the argument
still goes through the regular frozen-string conversion.

## Regression test

`test/test_nilpy_one_char_string.npy`, wired into `make test-nilpy`; output
diffed against CPython running the same file.

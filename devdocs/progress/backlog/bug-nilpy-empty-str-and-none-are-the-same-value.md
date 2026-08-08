---
track: N
prio: 40
type: bug
summary: "`\"\" is None` answers TRUE for a NilPy str: Pascal's empty AnsiString IS a nil handle, so the None sentinel and the empty string are indistinguishable — contradicting pylib's own comment that they are not."
---

# `""` and `None` are the same value for a NilPy str

```python
class E:
    def empty(self) -> Optional[str]:
        return ""
    def plain(self) -> str:
        return ""

print(E().empty() is None)   # CPython False   pxx True
print(E().plain() is None)   # CPython False   pxx True
print(len(E().empty()))      # both 0
```

## Why it matters

NilPy's whole None-for-str design rests on the two being distinguishable.
`pystr_none` returns a nil handle and `pystr_is_none` tests `Pointer(s) = nil`,
and pylib's comment states the assumption outright:

> a NilPy str that is None has a nil handle, a real string (including "") does
> not

Measured, that is FALSE — an empty AnsiString is nil in this runtime, so every
`is None` test on a str also fires for `""`. Ordinary Python code branches on
exactly that difference (`if s is None:` versus `if s == "":`), and here both
answer the same.

It also bounds what any fix in this family can do: a bridge that boxes "a nil
str handle" as None — which is the obvious way to make a host method's None
survive — would silently convert every returned `""` into None. That approach
was tried and abandoned for this reason while fixing
[[bug-nilpy-return-none-from-a-str-returning-def-yields-the-text-None]].

## PRE-EXISTING

Identical under `stable_linux_amd64/default/pinned`.

## Shape of the fix

The sentinel needs a representation that "" cannot collide with. Options worth
weighing rather than guessing between: a distinguished non-nil handle for None;
a separate variant tag for a None-str; or making str-typed Optionals variants
outright and accepting the cost. This is a model decision — consider a Track U
`decide-` ticket rather than picking one in passing, since
[[bug-nilpy-non-ascii-string-surface-measured]] and
[[bug-nilpy-encode-ignores-the-codec]] are already circling the same model.

## Gate

The three lines above matching CPython, `test_nilpy_none_str_field.npy` extended
with the "" case it currently documents as NOT asserted, plus the per-fix loop.

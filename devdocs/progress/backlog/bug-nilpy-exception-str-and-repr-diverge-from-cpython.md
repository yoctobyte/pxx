---
track: N
prio: 40
type: bug
---

# Exception `repr()` is the default object repr, and KeyError's `str()` drops its quotes

```python
try:
    raise KeyError("inner")
except KeyError as e:
    print(str(e), repr(e))

try:
    {}["nope"]
except KeyError as e:
    print(str(e))
```

| | CPython | pxx |
| --- | --- | --- |
| `repr(KeyError('inner'))` | `KeyError('inner')` | `<__main__.KeyError object at 0x...>` |
| `str(KeyError('inner'))` | `'inner'` (quoted!) | `inner` |
| `str()` of a real missing-key error | `'nope'` | `key not found` |
| `repr(ValueError('v'))` | `ValueError('v')` | `<__main__.ValueError object at 0x...>` |

Three separate things:

1. **No `__repr__` on exceptions.** Every exception falls back to the default
   object repr, so `repr(e)` prints an address. `ClassName(args)` is what
   CPython prints, and it is what appears in logs and in `%r` formatting.
   The @dataclass `__repr__` generator landed 2026-08-09 does exactly this shape
   already (class name, parenthesised arguments) — the exception case wants the
   same builder over `e.args`.

2. **`KeyError.__str__` is the REPR of its argument**, uniquely among builtin
   exceptions — `str(KeyError('inner'))` is `"'inner'"`, with quotes. It reads
   like a quirk and it is, but it is also what every "key not found" message in
   real logs looks like, so a diff against CPython output will trip on it.

3. **A genuine missing-key raise loses the key entirely**, reporting the fixed
   text `key not found`. That is the most useful of the three to fix: the key is
   the whole content of the message, and without it a KeyError says nothing.

## Found by

An exception/class-hierarchy sweep against CPython. Everything else in that
sweep matched exactly — custom exception classes, `super().__init__`, catching
by base class, tuple `except`, `else`/`finally` ordering, `type(e).__name__` —
so these three are the residue.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over `str`/`repr`
of KeyError, ValueError, a bare `Exception`, a user-defined subclass, the
zero-argument and multi-argument forms, and a real missing-key lookup.

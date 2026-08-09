---
track: N
prio: 40
type: bug
---

# Exception `repr()` is the default object repr (KeyError's message: FIXED 2026-08-09)

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

## 2026-08-09 — items 2 and 3 FIXED; item 1 (repr) still open

A missing key now reports the KEY. All four raise sites went through one keyless
`PyKeyError`, so they all had the key in scope and all four now pass it.

The message is built with **`pyvar_repr`, not `pystr_of`**, which fixes item 2
at the same time and for free: CPython's KeyError is the one builtin exception
whose `str()` is the REPR of its argument, so a missing string key now reports
`'nope'` with the quotes and a missing int key reports `7` without them. A
str-based fix would have passed the int case and failed the str one — which is
why `test/test_nilpy_keyerror_names_the_key.npy` asserts both kinds, plus an
empty-string key, a key containing a quote, and all four raise sites.

**Item 1 is untouched:** `repr(e)` on any exception is still the default object
repr (`<__main__.KeyError object at 0x...>` where CPython prints
`KeyError('nope')`). The test says so and deliberately does not pin it — the
current answer contains an address and is not even stable run to run.

The @dataclass `__repr__` generator that landed the same day is the shape that
half wants: class name, parenthesised arguments. It would need `e.args`, which
is its own open item.

## 2026-08-09 (later) — item 1 (repr) FIXED for everything except KeyError

`repr(e)` on an exception with no `__repr__` of its own now renders
`ClassName('msg')` instead of `<__main__.ValueError object at 0x...>`. Covers the
builtins and user-defined subclasses, in `%r`, inside containers, and for caught
exceptions. Pinned by `test/test_nilpy_exception_repr.npy`.

**KeyError is deliberately excluded and keeps the address form.** It cannot be
rendered correctly from a Message alone: its message is stored ALREADY REPR'D so
that `str()` matches CPython's quirk, so quoting it again gives
`KeyError("'nope'")`, and not quoting it gives `KeyError(k)` for a
user-constructed `KeyError("k")`. Both are wrong in opposite cases, and which one
you hit depends on WHO RAISED IT. Neither ships. An address is obviously
unhelpful; a wrongly quoted key would look authoritative.

The empty-message case renders as `ValueError()`. `ValueError('')` is
indistinguishable from it given one Message field, and the zero-argument
spelling is far the commoner.

**Both of those are the same root, and it is `e.args`:** a pxx Exception carries
a single Message string where Python carries an argument tuple. Until that
exists, KeyError's repr and the `ValueError('')` case cannot be right. That is
the next piece of this ticket.

## Also found, still open: `str()` of a CONSTRUCTED exception

`str(ValueError("v"))` on an exception that was never raised gives the address
form, while a CAUGHT one gives its message — two different paths. Pre-existing,
found while testing the above, and deliberately not pinned by the new test.

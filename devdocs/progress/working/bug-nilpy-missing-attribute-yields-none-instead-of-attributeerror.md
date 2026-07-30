---
track: N
prio: 65
type: bug
---

# Reading an attribute that does not exist yields None — and on None it can yield a STRING

```python
x = None
print(x.foo)          # CPython: AttributeError    pxx: None
print(x.upper())      # CPython: AttributeError    pxx: 'NONE'

class K:
    pass2 = 1
k = K()
print(k.nope)         # CPython: AttributeError    pxx: None

d = {}
print(d.get("k").x)   # CPython: AttributeError    pxx: None
```

`None.upper()` returning `'NONE'` is the one to look at first: the receiver was
stringified to `"None"` and the string method applied to that text. So a missing
value does not merely propagate as None — it can turn into plausible *data*.

## Measured

| expression | CPython | pxx |
| --- | --- | --- |
| `None.foo` | AttributeError | `None` |
| `None.upper()` | AttributeError | **`NONE`** |
| `obj.nope` (attribute never assigned) | AttributeError | `None` |
| `d.get(missing).x` | AttributeError | `None` |
| `None[0]` | TypeError | TypeError ✓ |
| `len(None)` | TypeError | TypeError ✓ |
| `for v in None` | TypeError | TypeError ✓ |
| `None()` | TypeError | TypeError ✓ (fixed — see below) |

The subscript / len / iterate / call paths all raise correctly. It is
specifically ATTRIBUTE access that answers None.

## Why it matters more than it looks

This is the same failure shape as
[[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]]: a wrong value
travelling far from its cause. A typo in an attribute name, or a `dict.get` that
missed, yields None and the program carries on — and the first place it goes
wrong is wherever that None is finally used, which may be nowhere near.

It also interacts with the deliberate `None -> 0` coercion in `pyvar_to_int`
(kept for the `Optional[int]` contract uforth depends on): a misspelled
attribute becomes None, which then becomes 0 in a numeric context, and the
arithmetic silently answers with a zero nobody wrote.

## Note on dynamic attributes

NilPy supports genuinely dynamic attributes (`obj.name = v` stored in a global
dict keyed by address + name, used by uforth for lazy state), so "not a declared
field" cannot itself be the error condition — the lookup has to miss the dynamic
table too before it raises. That is presumably why the miss path returns a
default instead of raising, and it is the thing to be careful about when fixing:
`hasattr` must keep working, and `getattr(o, n, default)` must still return the
default rather than raise.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering the table
above with CPython's own output, and explicitly: `hasattr(o, 'x')` False without
raising, `getattr(o, 'x', d)` returning `d`, and a dynamic attribute set then
read back.

## Fixed separately while measuring this

`None()` raised a bare `Exception` carrying the text `TypeError: ...` rather
than a `TypeError`, so `except TypeError:` missed it while `except Exception:`
caught it. That raise lived in `pyeval.pas` and was the last of the family the
[[bug-nilpy-pytypeerror-halts-instead-of-raising]] sweep missed (it only swept
`pylib.pas`). Converted, and covered by
`test/test_nilpy_typeerror_is_catchable.npy`.

## CLOSED

Both measured causes fixed. `pydynattr_get`'s miss branch now raises
`AttributeError` — confirmed safe for `hasattr`/`getattr`, which resolve
through `pydynattr_has` directly and never reach the miss branch of
`pydynattr_get` at all. Split into two pylib procs so the error MESSAGE is
safe to build in both cases the ticket's receivers can take: a class-typed
receiver (`obj` is always a genuine object or nil) keeps `pydynattr_get`;
a variant receiver (a for-loop element, `d.get(k)`, an unannotated parameter)
gets a new `pydynattr_get_v`, which checks the runtime TAG before ever
touching `.ClassName` — the naive unwrap would have `ClassName`'d a str/int/
float/bool variant's reinterpreted payload, a new crash the ticket's own
matrix does not cover but the general receiver shape (`for` variables,
`d.get()`) very much reaches.

`None.upper()` (and the same for any str method on a non-str variant) is
fixed separately: `PyParseVariantMethod` used to stringify the receiver via
`pystr_of` unconditionally before dispatching the method, and `pystr_of`
correctly renders None as `'None'` (that part is not a bug — `str(None)` is
supposed to say that) — the bug was calling a METHOD through that text.
Fixed with a runtime tag guard (`pyvar_is_strtag`) that raises via a new
`pydynattr_no_method` before the str conversion runs, whenever the receiver
is not actually string-shaped. The receiver is hoisted into a hidden temp
first since it is now read twice (guard, then conversion) and is not always
side-effect-free — `d.get(k).upper()`, the ticket's own repro of the OTHER
half of this bug, is exactly such a case.

Test: test/test_nilpy_missing_attribute_raises.npy, the full table from this
ticket plus the hasattr/getattr/dynamic-attribute-round-trip guards the gate
asked for and a genuine str-variant method call (the pre-existing, must-keep-
working path). Gate: make test-nilpy green, self-host fixedpoint, testmgr
--tier quick.

Ticket closed.

---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`b'abc'.__getitem__(0)` prints nothing where CPython prints 97 — a silent wrong value, not a diagnostic. `b'abc'.__len__()` on the same receiver is correct, and `str.__len__` / `str.__getitem__` raise AttributeError for methods CPython has."
status: done
owner: frank1-AN
---

# `bytes.__getitem__` returns empty instead of the byte value

Filed 2026-08-26 while resolving
[[bug-n-hasattr-through-an-untyped-parameter-is-always-false]] — found by asking
whether `hasattr` could honestly answer True for the subscript dunders, which is
answered by whether the CALL works. For bytes it half works, and the half that
does not is silent.

## Measured (self-hosted at the fix's sha; the receiver is an untyped parameter)

```python
def c(x):
    return x.__getitem__(0)
def n(x):
    return x.__len__()
print(n(b'abc'), c(b'abc'))       # CPython: 3 97      pxx: 3 <empty>
print(n('abc'),  c('abc'))        # CPython: 3 a       pxx: AttributeError
```

| | CPython | pxx |
| --- | --- | --- |
| `b'abc'.__len__()` | 3 | 3 |
| `b'abc'.__getitem__(0)` | 97 | **(empty — silent wrong value)** |
| `'abc'.__len__()` | 3 | raises `'str' object has no attribute '__len__'` |
| `'abc'.__getitem__(0)` | `a` | raises `'str' object has no attribute '__getitem__'` |
| `[7,8].__getitem__(0)` | 7 | 7 |
| `{'a':1}.__len__()` | 1 | 1 |

## Two defects, one probe

1. **`bytes.__getitem__` is a silent wrong value.** `PyPylibMethodAlias` maps the
   subscript protocol onto pylib's spellings for **TPyDict** (`fetch`/`store`/
   `remove`/`count`) and **TPyList** (`at`/`put`/`pop_at`/`count`) and has **no
   TPyBytes arm** — yet `TPyBytes` declares the very same `count` and
   `at(i): Integer`. So the call resolves through some other route and comes back
   empty rather than declining. Find out which route before adding the table row;
   a missing alias should produce "no such method", and this produces a value.
2. **str has no dunder methods at all.** `'abc'.__len__()` / `.__getitem__(0)`
   raise, so `len('abc')` and `'abc'[0]` work while their method spellings do
   not — the same one-capability-two-spellings shape
   [[bug-n-a-builtin-types-method-cannot-be-called-unbound]] recorded for dict.
   `PyStrMethodInfo` has no rows for them.

## Why it is filed and not folded in

`hasattr(b'ab', '__len__')` and `hasattr('s', '__len__')` are False today, and
that is the *honest* answer while the call cannot be honoured for one of them and
is wrong for the other — the same rule
[[bug-nilpy-hasattr-on-a-builtin-container-or-str-answers-false]] applied to
float methods ("answering True would be a claim the call cannot honour").
`hasattr` becomes correct for both **for free** when this lands, because the
predicate reads those same tables. Adding the alias rows first, on top of a call
path that already returns the wrong value for `bytes.__getitem__`, would build on
the bug.

## Gate

The table above, diffed against CPython, plus `b'abc'[0]` and `'abc'[0]` (the
operator spellings, which must keep working) and the `hasattr` rows for the four
dunders once the calls are right.

## Resolution — 2026-08-27

Fixedpoint `3e2250b8a5e9`, `tools/gate.sh quick` GREEN.
Test: `test/test_nilpy_subscript_dunder_spellings.npy` + `.expected`,
registered in the Makefile. Every row of the ticket's table now matches CPython,
through BOTH receiver routes (untyped parameter and direct receiver).

**The ticket said "find out which route before adding the table row; a missing
alias should produce 'no such method', and this produces a value." That was the
right instinct and here is the answer — it is worse than a wrong value.**

The variant-receiver dispatcher builds its candidate set by asking
`PyMethNameFor` of each class. With no TPyBytes arm, TPyBytes never became a
candidate, so a bytes receiver fell through to the **FALLBACK arm — TPyList —
and ran list code over a TPyBytes**. Measured:

| call | answer | what actually ran |
| --- | --- | --- |
| `x.__len__()` | `3` — **right** | `TPyList.count` reads `FLen`, at the same offset in both classes. Correct **by accident**. |
| `x.__getitem__(0)` | *(empty)* | `TPyList.at` read `FItems` where `FData` is |
| `x.__setitem__(0, 65)` | **corrupts** | `TPyList.put` wrote a 16-byte variant slot over the byte buffer: `bytearray(b'abc')` → `[1, 0, 0]` |

The accidentally-correct `__len__` row is why this looked like an isolated
`__getitem__` defect for a whole ticket. The `__setitem__` row is memory
corruption from ordinary Python and was not in the ticket at all.

**Three changes, and the third is the general one:**

1. **A TPyBytes arm in `PyPylibMethodAlias`** — `__getitem__`→`at`,
   `__setitem__`→`put`, `__len__`→`count`. No `__delitem__`: TPyBytes has no
   `pop_at`, and aliasing it elsewhere would delete by the wrong rule silently,
   the same call the list arm already makes about `remove`.
2. **`__len__` / `__getitem__` rows in `PyStrMethodInfo`** — `pystr_len` and
   `pystr_charat`. `charat`, not `at`: Python's `s[i]` is a one-CHARACTER str
   and `pystr_at` yields a lead byte, so this is literally the call the
   subscript lowers to. No `__setitem__`: CPython's str has none either.
3. **`PyAnyClassDeclaresMeth` now asks `PyMethNameFor`, not `FindUMeth`.**
   Step 2 alone REGRESSED step 1 — a bytes receiver started raising
   `AttributeError` — and the bisect is the finding: that predicate decides
   whether a str-method name is ambiguous enough to need dual dispatch, and it
   looked for the name **as written**. `find` is declared literally on TPyBytes
   and dual-dispatched fine; `__len__` is reached through an alias, so the
   predicate answered False, the str arm won unopposed, and the bytes receiver
   hit the str arm's "not a string tag" branch. `PyMethNameFor`'s own header
   says "Every resolution path calls this instead of applying the table by
   hand" — this path applied it by hand. It is the same failure its neighbour's
   header records for `title` and `count`, one level further in.

**`hasattr` became correct for free, exactly as predicted** — it reads the same
tables. `hasattr(b'ab', '__len__')` and `hasattr('s', '__getitem__')` were False
(honest while the call was wrong or impossible) and are now True.

**Canaries, 24, all green, named one by one:** `builtin_subclass_dunder_dispatch`,
`dynamic_dispatch`, `dispatch_result_class`, `bytes_methods`,
`bytearray_vs_bytes`, `bytes_setslice_variant`, `bytes_membership`,
`bound_method_value_receiver_shapes`, `hasattr_builtin_receivers`,
`hasattr_untyped_parameter`, `hasattr_variant_receiver`, `getattr_dunder`,
`str_chars_through_a_variant`, `str_counts_characters`, `builtin_shadow_slice`,
`str_as_an_iterable_argument`, `lib_mimic_collections_abc`, `bool_protocol`,
`dunder_len_contains`, `augmented_dunder_subscript`,
`augmented_subscript_variant_base`, `attr_off_subscript_of_call_result`,
`bytes`, `bytes_ann`, `bytearray_ctor`, `bytes_decode`. The dispatch and hasattr
ones matter most — change 3 touches a predicate every ambiguous call consults.

## Log
- 2026-08-27 — resolved, commit 2be0c863f.

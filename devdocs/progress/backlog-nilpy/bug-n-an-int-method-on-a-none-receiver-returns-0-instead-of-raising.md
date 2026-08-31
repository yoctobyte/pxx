---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`None.bit_length()` returns 0 where CPython raises AttributeError — the int-method arm on a variant receiver unboxes without checking the tag, and None's payload reads as the integer 0. dict/list/str receivers do raise, so None is the one shape that answers."
---

# An int method on a `None` receiver returns 0 instead of raising

Filed 2026-08-26 while resolving
[[bug-n-hasattr-through-an-untyped-parameter-is-always-false]], which fixed the
PREDICATE half of the same over-claim (`hasattr(None, 'bit_length')` was True and
is now correctly False). This is the CALL half, and it is the worse one because
it produces a value.

## Measured (self-hosted at that fix's sha; receiver is an untyped parameter)

```python
def c(x):
    return x.bit_length()
```

| receiver | CPython | pxx |
| --- | --- | --- |
| `7` | 3 | 3 |
| `{'a': 1}` | AttributeError | raises (`expected a number, got object`) |
| `[1, 2]` | AttributeError | raises (`expected a number, got object`) |
| `'abc'` | AttributeError | raises (`expected a number, got str`) |
| **`None`** | AttributeError | **0 — no error at all** |

## Cause

`PyIsIntMethodBaseTk(tk, nm)` answers `(tk = tyVariant) and not
PyAnyClassDeclares(nm)` — i.e. for a variant receiver it is a statement about the
PROGRAM, not the receiver, so the int-method intercept claims every variant and
unboxes it. Three of the four wrong receivers are caught downstream by the unbox
refusing a non-number; `None`'s VT_EMPTY payload reads as `0` and sails through.

The predicate side of this was fixed by asking `PyIsIntBaseTk` (a statement about
the receiver) and emitting run-time tag tests for the variant case — see
`PyHasAttrRuntimeChain`. The call has the same options: guard the intercept with
`pyvar_is_inttag`-shaped tests the way `PyParseVariantMethod`'s str and float
arms already do, and raise `pydynattr_no_method` otherwise. Those two arms are
the model; the int one never got it.

Note the wrong *messages* on the other three rows are error-reporting parity and
low prio by CLAUDE.md's rule; the `None` row is a silent wrong value and is why
this is filed as a bug rather than a compat item.

## Gate

The table above diffed against CPython (the message text normalised or the row
asserted as "raises"), plus `to_bytes` and `bit_count` on the same receivers, and
`(7).bit_length()` / `True.bit_length()` still answering 3 / 1.

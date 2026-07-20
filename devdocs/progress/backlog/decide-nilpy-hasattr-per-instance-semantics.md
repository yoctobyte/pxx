---
track: U
prio: 35
type: decide
---

# decide: should NilPy's hasattr answer per-INSTANCE or per-CLASS?

Raised 2026-07-20 implementing hasattr/getattr for the uforth drive.

## The fork

Python's `hasattr(o, "x")` asks whether the attribute has been ASSIGNED on that
particular object. NilPy classes declare their fields statically and every
field is zero-initialised, so "declared" and "assigned" are not distinguishable
at runtime.

Shipped behaviour: resolved at COMPILE time against the class's declared
fields. A declared field reports True even before the first assignment.

## Where it differs in practice

uforth's idiom:

```python
if not hasattr(self, "_tok_current"):
    self._tok_in_string = False
    self._tok_quote_char = ""
    self._tok_paren_depth = 0
```

Under CPython the block runs once; under NilPy it never runs. It happens to be
harmless HERE — the three fields zero-initialise to exactly those values — but
that is luck, not equivalence. A guard whose body did something non-trivial
(allocating a list, opening a file) would be silently skipped.

## Options

1. **Keep compile-time class-based** (shipped). Free, no per-object state,
   matches "fields are declared". Silently skips first-time-init idioms.
2. **Per-instance "assigned" bit.** Faithful, but costs a bit per field per
   object and a write on every assignment — for a feature 4 sites use.
3. **Reject `hasattr` on a field the class declares** and require the corpus to
   use an explicit sentinel (`self._tok_current is None`). Loud instead of
   silent; needs a corpus edit, which the uforth ticket forbids (it must run
   UNMODIFIED).

Recommendation: keep 1, but consider a `--strict` warning when `hasattr` is
used as a first-time-init guard, since that is the case where 1 is wrong.

## Related

[[feature-nilpy-corpus-uforth]]. Option 3 conflicts with that ticket's
"unmodified" requirement, which is itself worth confirming.

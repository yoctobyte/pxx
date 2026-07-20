---
track: N
prio: 45
type: feature
---

# NilPy: `None` as a first-class variant value (VT_EMPTY)

Hangs off [[feature-nilpy-corpus-uforth]]. Filed 2026-07-19 while sizing
[[feature-nilpy-dict]].

## The gap

`None` works today only where it can be represented as a *sentinel*:

- `Optional[SomeClass] = None` -> nil pointer, and `x is None` is a pointer
  compare. Correct, and it covers most of uforth's 115 `is None` /
  `is not None` sites.
- `Optional[int] = None` -> 0. Documented caveat in `PyAnnTypeAt`: an
  `Optional[int]` whose legitimate value is 0 aliases the sentinel.

What does NOT work is `None` as a value flowing through an `Any` (variant):
`d.get(k)` on a missing key, a list slot holding None, a function returning
`Optional[Any]`. The runtime already HAS the representation — `VT_EMPTY = 0`
in `defs.inc`, "unassigned slot" — it is simply not wired to the language.

## Shape

- `None` in an expression position where the target is a variant -> a variant
  literal with tag `VT_EMPTY`.
- `x is None` / `x is not None` on a variant-typed x -> tag compare against
  `VT_EMPTY`, NOT the current payload compare (which would call a
  VT_EMPTY-tagged slot equal to integer 0 — a silent wrong answer, so this
  ordering matters: land the tag compare in the same change).
- Truthiness: `if x:` on a variant must treat VT_EMPTY as false.
- `print(None)` -> `None`, matching CPython.

## Neighbouring gap, found 2026-07-20

Printing a variant that holds an OBJECT (VT_OBJECT) emits NOTHING — an empty
line, silently. It shows up the moment for-in lands, because the loop variable
over a list of objects is exactly that:

```python
for w in vm.order:
    print(w)          # CPython: <__main__.Word object at 0x...>   pxx: blank
```

A class-typed value prints its POINTER as an integer instead, which is at
least visible. Neither matches CPython, and neither can be diffed against it
(the address varies), so this is not a test-gate item — but a blank line is
worse than a pointer for anyone debugging, and both should probably become
something like `<Word object>`. Same writer (`EmitWriteVariant`) as the None
case above, so it is one change, not two.

## Why it is filed separately from dict

Dict v1 ([[feature-nilpy-dict]]) deliberately ships `.get(k, default)` (the
2-argument form) and the mapping core, whose semantics need no None. The
1-argument `.get(k)` on a MISSING key is exactly this ticket — and it is the
form uforth uses at ~20 of its 21 `.get` sites, so dict is not really
finished for the corpus until this lands. Sequence: dict core, then this,
then re-drive.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick`
+ self-host byte-identical + `make fpc-check`.

## Log

- 2026-07-20 (1933d8d0) — landed: None PRINTS as None (variant writer + the bare
  literal), `is None` / `is not None` on a variant is a TAG test through
  pyvartag (it was a payload compare answering True for integer 0 — the silent
  wrong this ticket warned about, now pinned by the test's `0 is None → False`),
  `None` as a list/set ELEMENT stores VT_EMPTY via pylib's new `pynone`, and
  pylib's str()/repr() of an empty slot spell None. The neighbouring VT_OBJECT
  gap is closed to the extent it can be: an object slot prints `<object>`
  instead of a blank line (CPython's spelling carries an address, so it is not
  oracle-diffable). Regression test `test/test_nilpy_none.npy`.
- **Remaining, deliberately not half-fixed:** `d[k] = None` still stores 0.
  That statement is parsed as an assignment EXPRESSION by the shared parser
  (the value-bearing store), so it never passes through the NilPy assignment
  paths where the other None rewrites live. The fix wants the general rule —
  in PyExprMode a bare `None` is a VARIANT None, with the sentinel forms
  (`Optional[int]` → 0, `Optional[Class]` → nil) restored by
  PyCoerceAssignmentRHS at the annotated targets — rather than another
  per-site rewrite. Re-file or re-open with that shape.
- Also noted while testing: a def with NO return annotation (`def f(k: str):`)
  does not parse. Separate gap, not filed yet — mention it if it blocks a
  corpus drive.

- 2026-07-20 — moved back to `backlog/` rather than parked in `unfinished/`:
  everything that landed is green and gated, and what is left is one
  well-scoped item (the general "None is a variant in PyExprMode" rule above),
  not a half-applied change. Priority lowered to 45 to match the smaller
  remaining scope.

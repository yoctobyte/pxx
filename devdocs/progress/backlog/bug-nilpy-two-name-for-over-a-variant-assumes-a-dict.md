---
track: N
prio: 55
type: bug
summary: "NilPy: `for k, v in <variant>` is lowered as a DICT unconditionally, so iterating a variant-held list of pairs raises TypeError: expected a dict, got object — the same list unpacks fine when its type is statically known"
---

# `for k, v in <variant>` assumes a dict, so a list of pairs raises

- **Type:** bug (ordinary Python refused) — **Track N**
- **Found:** 2026-08-06, bughunting. Surfaced writing a plain hash table:
  `for kk, vv in self.buckets[self._h(k)]:` — iterating a bucket (a list of
  `(key, value)` tuples) reached through a subscript.
- Loud, not silent, which is why this is prio 55 rather than higher.

## Measured (self-hosted at `54fbd2754`)

```python
pairs = [("a", 1), ("b", 2)]
for k, v in pairs:              # OK — static type is a list
    print(k, v)

class C:
    def __init__(self): self.rows = [("a", 1), ("b", 2)]
    def show(self):
        for k, v in self.rows:  # OK — field type is known
            print(k, v)

box = [[("a", 1), ("b", 2)]]
for k, v in box[0]:             # TypeError: expected a dict, got object
    print(k, v)
```

The only difference is whether the container's type is statically known. Any
dynamically-typed route — a list element, an unannotated parameter, a value out
of a dict or a parsed structure — hits it.

## Cause

`compiler/pyparser.inc`, `PyParseForIn`:

```pascal
  if (not isStr) and (contTk = tyVariant) and (name2 <> '') and (not enumMode) then
  begin
    vSym := FindProc('pydict_v');
    …
```

Two loop names + a variant container is taken to mean a dict, and the container
is unboxed with `pydict_v`, which raises when the value is not one. The comment
there records the case it was written for — `for option, value in
options.items()` where `options` came out of another dict — which is real; it is
the *unconditional* part that is wrong.

The parser already knows the other reading: `pairMode` handles "the pairs come
from ONE list whose elements are unpacked". It is simply unreachable once the
static type has been erased to a variant, so the dict arm wins by default.

## Suggested direction

Decide at RUN time, since that is the only place the answer exists. The cheapest
shape is probably a pylib helper — `pyiter_pairs_v(v)` — that yields a sequence
of 2-element pairs for EITHER input: a dict contributes its items, a list is
already pairs, anything else raises with a message naming both possibilities.
The lowering then has one arm instead of a guess.

Whoever takes it should check what the dict arm does today before assuming the
helper is free: if `pydict_v` + iteration already materialises items, the helper
costs nothing extra; if it iterates the dict in place, materialising would be a
regression for the dict case and the arm needs a tag test rather than a
conversion. **Measure that before choosing** — do not infer it from the shape of
the code.

## Gate

Per-fix loop. A `.npy` test iterating pairs both ways (a variant-held list of
tuples, a variant-held dict via `.items()`, and a variant holding neither, which
must raise) plus the statically-typed controls, diffed against CPython with
`tools/pydiff.py`.

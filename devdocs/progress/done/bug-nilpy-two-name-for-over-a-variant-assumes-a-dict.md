---
track: N
prio: 55
type: bug
summary: "NilPy: `for k, v in <variant>` is lowered as a DICT unconditionally, so iterating a variant-held list of pairs raises TypeError: expected a dict, got object — the same list unpacks fine when its type is statically known"
status: done
owner: claude-A-N
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

## 2026-08-07 — FIXED, and the evidence was already in the parser

The ticket's suggested direction was a run-time `pyiter_pairs_v` helper, on the
reasoning that the dict-or-list question can only be answered at run time. It
turns out it does not have to be: the parser already knows, and had thrown the
answer away four lines earlier.

**A two-name for-in header STRIPS a trailing `.items()` at token level**
(`PyItemsSuffixAhead`, then `Tokens[itemsDot].Kind := tkColon` so the expression
parser stops at the dict). So by the time the variant arm runs, `.items()` is
gone from the token stream — and `itemsDot` is the one surviving witness that it
was ever there. That witness is exactly the discriminator:

- `itemsDot >= 0` — the user wrote `.items()`, the container IS a dict, keep the
  `pydict_v` + `keylist`/`vallist` lowering unchanged. This is the case the arm
  was written for (songformatter's dict of dicts) and it is untouched.
- `itemsDot < 0` — bare. Python iterates the container and UNPACKS each element,
  which is `pairMode` (already fully general — it handles three names too, which
  the dict path never did).

One condition, no new runtime helper, and the dict case keeps its exact cost —
which was the thing the ticket said to measure before choosing. (Measured
anyway: the dict path materialises `keylist` AND `vallist`, so a
list-of-pairs helper would not have been free for it either.)

**A second divergence fell out, and it is why the fix is not "make pairMode the
fallback for a dict too".** `for k, v in <bare dict>` is NOT `.items()` in
Python — it iterates the KEYS and unpacks each one, so `{"ab": 1}` yields
`k='a', v='b'`. pxx answered `k='ab', v=1`. With the arm gated, the bare form
now goes through `pylist_v`, which needed a `TPyDict` case: `list(d)` and
`for x in d` are both the key sequence. That also fixes the SINGLE-name form —
`for k in <variant-held dict>` refused with "expected a str or a list" — which
was the same missing case seen without the two-name distraction.

**Verified**, self-hosted build at this commit, diffed byte-identical against
CPython: the new `test/test_nilpy_for_two_names_over_a_variant.npy` (static and
field-typed controls; erased routes via a list element, an unannotated
parameter and a dict value; three names; `.items()` on a variant-held dict two
ways; the bare-dict key unpacking; the single-name bare dict and `list(d)`; and
a variant holding neither, which still raises TypeError). Plus a sweep: every
`test/*.npy` containing a two-name for-in re-diffed against CPython — 19 match;
the two that do not (`dict_mutation_during_iteration`, `dict_comprehension`) are
byte-identical to `pinned`, i.e. pre-existing divergences and not regressions,
and `nested_for_target_fail` is a deliberate compile-failure test.
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.

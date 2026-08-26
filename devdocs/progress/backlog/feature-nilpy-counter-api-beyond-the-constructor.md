---
track: N
prio: 35
type: feature
blocked-by: []
summary: "collections.Counter counts and reads correctly now, but three ordinary CPython spellings are missing: `Counter({...})` (no dict overload — a COMPILE error listing the three that exist), `.elements()` (AttributeError), and Counter arithmetic `c1 - c2` / `c1 + c2` (TypeError). All three wall LOUDLY, which is the right failure mode, so this is a feature gap and not a bug."
status: backlog
owner: —
---

# Counter's API beyond the constructor

Split out of
[[bug-n-from-collections-import-counter-binds-something-that-always-answers-zero]]
(fixed: `Counter("aab")["a"]` now answers 2, and `Counter.update(str)` counts
characters). While probing the boundary of that fix, three more `Counter`
spellings turned out to be absent. They are filed separately because they are a
different thing — the fixed ticket was a **silent wrong value**, these are
**missing features that fail loudly**, which is the behaviour
`PyImportIsConsumedOnly`'s consume-and-ignore rule promises.

Measured at `dev` 2026-08-26, self-hosted binary at the Counter fix:

| spelling | CPython | NilPy today |
| --- | --- | --- |
| `Counter({"a": 2, "b": 1})` | works | **compile error**, listing `Counter()` / `Counter(class)` / `Counter(AnsiString)` |
| `Counter("aab").elements()` | `['a','a','b']` | `AttributeError: 'TPyDict' object has no attribute 'elements'` |
| `Counter("aab") - Counter("a")` | `Counter({'a': 1, 'b': 1})` | `TypeError: unsupported operand type(s) for this operator` |

Also `Counter("aab") + Counter("a")`, `.subtract()`, `.total()`, and
`most_common(n)` beyond the two arities already present — worth a sweep rather
than one addition at a time.

## Notes for whoever takes it

- `TPyDict.update(d: TPyDict)` **already** does Counter-mode addition correctly
  (it `pyvar_to_int`s both sides and adds). So `Counter(d: TPyDict)` is the same
  three-line delegation the string and list arms now use, and the `-`/`+`
  operators are a walk over `keylist`/`vallist` on top of it. The counting logic
  exists; what is missing is the surface.
- `Counter` is a **mode on `TPyDict`**, not a subclass (see the `FCounterMode`
  note in pylib.pas — a subclass loses subscript assignment,
  `bug-pascal-subclass-inherited-members`). So `elements()` and the operators go
  on `TPyDict` guarded on the mode, exactly like `update` and `most_common`.
- CPython's `-` **drops non-positive counts** and `+` keeps only positive ones;
  `subtract()` is the one that keeps zero and negative. Easy to get backwards.
- Keep one counting loop. The fixed ticket's whole shape was a second copy of
  the string-counting loop drifting from the first.

## Where

`compiler/builtin/pylib.pas` — the `Counter` overload set (~2229 interface,
~7685 bodies) and the `TPyDict` Counter-mode members (`FCounterMode`, `update`,
`most_common`).

## Gate

Track N: `make compiler/pascal26` + a `.npy` test with a **CPython-generated**
`.expected`, wired into `test-core` next to
`test/test_nilpy_counter_from_a_string.npy`.



## Resolved 2026-08-04 — the split the ticket described, at one name

The ticket's instruction was right: keep a Self-returning entry point for the
desugars and give the Python-visible method the None result. What the survey it
asked for showed is that **only ONE of the four needed the split.**

`grep` for the frontend sites, as the ticket suggested:

| site | uses the result as |
| --- | --- |
| list LITERAL desugar (2 sites) | **a chained VALUE** — `Create.append(a).append(b)…` |
| comprehension / dict-comprehension body | a statement |
| `*` unpack into a literal (`extend`) | a hoisted statement |
| `+=` on a list (`extend`, 3 sites) | the statement node |

So `sort`, `reverse` and `extend` simply return `pynone` now — nothing needed
their Self result. Only `append` is split: the Self-returning body is renamed
`append_self` and the two literal-desugar sites call that, while the
Python-visible `append` delegates and returns None.

Verified there is no chained use inside the runtime either — the `:=` hits in
`pylib`/`pyeval` are all `for … do X.append(…)` loop headers, not assignments of
the result.

### Verified

`test/test_nilpy_list_mutators_return_none.npy`, wired into `make test-nilpy`:
all four asserted with **`is None`** rather than by printing (so the test cannot
pass on a coincidence of how None renders), the mutation still visible after
each, `if l.append(x):` taking the FALSE branch — the falsiness edge the ticket
called the sharper one — and list literals, a comprehension, a nested
comprehension, a dict comprehension, `+=` and `sorted()` all unchanged. Diffed
against CPython, identical. `tools/gate.sh quick` GREEN, self-host
byte-identical.

## Log
- 2026-08-04 — resolved.

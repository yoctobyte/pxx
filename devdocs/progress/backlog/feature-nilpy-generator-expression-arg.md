
## 2026-08-09 — the remaining hole was `set()`, and it was set()'s own

Swept every builtin that takes an iterable. Nine of ten already accepted a bare
generator expression — list, tuple, dict, sorted, sum, min, max, any, all. Only
`set(x for x in xs)` failed, and it failed to PARSE ("Expected: ), but got:
for"), which is why it read as a general genexpr limitation.

`set(...)` hand-rolls its argument instead of using the shared call-argument
loop, because it lowers to pylib's `pyset_of` and needs the result stamped with
the SET kind. That hand-rolled copy never learned the `PyBareGenExprAhead` check
the shared loop has: a second parser for one concept, disagreeing silently
(`devdocs/dev/normalise-dont-special-case.md`).

Fixed with the same two lines the shared loop uses, and the test now sweeps ALL
ten callees rather than just `set` — so an eleventh that hand-rolls its argument
fails here rather than in someone's program.

Found by compiling a realistic tokenizer, not by an API sweep: it took
`sorted(set(t.kind for t in toks))`, a shape nobody writes when probing genexprs
one builtin at a time.

Verified: `test/test_nilpy_genexpr_arg_callees.npy` against CPython, including
`if` filters, derived values, empty results, method-call iterables and a nested
genexpr. `gate.sh quick` GREEN.

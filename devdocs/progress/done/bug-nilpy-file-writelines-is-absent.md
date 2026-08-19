---
track: N
prio: 30
type: bug
blocked-by: []
commit: 89021e5c5
summary: "`f.writelines(lines)` raised 'TPyFile has no method writelines' — the ordinary way to write a list of lines. Added, taking any iterable through pyseq_of_obj and adding no separator, as CPython does."
---

# `f.writelines(...)` is absent

```python
with open(p, "w") as f:
    f.writelines(["a\n", "b\n"])     # pxx: TPyFile has no method writelines
```

Found 2026-08-15 by a CPython differential sweep of a script-shaped program
(open/write/read/readlines/iterate/append/split/format). Everything else in that
probe agreed exactly; `writelines` was the only wall, and it is loud.

## Fix

`TPyFile.writelines(const v: Variant)` — a variant parameter for the reason the
`write` row beside it documents (the call site picks an overload by name and
ARITY, so a dynamically-typed argument needs a variant-typed entry), and the
sequence comes from `pyseq_of_obj`, so a list, a tuple, a cursor, a range or a
user `__iter__` all work by the one chain. **No separator is added** — CPython's
`writelines` does not, the caller's strings carry their own newlines, and adding
one would be a plausible wrong answer rather than an error.

## Also found, NOT fixed here

`f.writelines(str(i) + "\n" for i in xs)` — a BARE generator expression as a
METHOD-call argument — fails with `undefined variable (i)`. The diversion that
handles this (`PyBareGenExprAhead`, at the ordinary-call site in `parser.inc`)
is not on the method-call path, so `"".join(x for x in xs)` and friends have the
same hole. Filed as [[bug-nilpy-bare-genexpr-as-a-method-argument-does-not-parse]].

## Gate

`test/test_nilpy_file_writelines.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: a list of newline-terminated strings, an EMPTY
sequence, a comprehension result, and a TUPLE of strings with no newlines at all
(proving no separator is inserted). `gate.sh quick` GREEN. Pinned
(`compiler/builtin/**`).

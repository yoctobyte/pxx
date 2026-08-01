---
summary: "NilPy: `dict([(\"a\",1)])[\"a\"]` and `\"abc\".encode().decode()` both SEGFAULT (exit 139, core dumped) on ordinary one-liners"
type: bug
track: N
prio: 70
---

# `dict(pairs)` subscript and `bytes.decode()` segfault

- **Type:** bug (NilPy, CRASH) — **Track N**
- **Opened:** 2026-08-01, from a differential sweep of the string/list/dict
  method surface against CPython (133 cases, self-hosted binary at `c7d64813b`).

## Measured

```python
d = dict([("a", 1)])
print(d["a"])            # CPython: 1      pxx: SIGSEGV (exit 139, core dumped)
```

```python
b = "abc".encode()
print(b.decode())        # CPython: abc    pxx: SIGSEGV (exit 139, core dumped)
```

Both COMPILE cleanly (`ok: ... procs=1039`) and die at run time. Neither uses a
user class or any dunder — these are plain stdlib idioms.

## Why these rank high

A crash with no diagnostic is worse to chase than a wrong value, and both are
ordinary spellings a real program would hit:

- `dict(list_of_pairs)` is the standard way to build a dict from `zip()`,
  `.items()`, or parsed input.
- `.encode()` / `.decode()` round-tripping is the standard way to move between
  `str` and `bytes`, e.g. around any socket or file API.

They are filed together because they were found in the same pass and both are
crashes, not because a shared cause is established. **Check whether they share
one** before fixing: both involve a pylib container built by one call and
consumed by another, so a wrong result type / missing retain on the intermediate
is a plausible common shape — but that is a hypothesis, not a diagnosis.

## First steps

`PXXDBG=a.ir:<proc>` on each (wrap in a `def` — the module-level dump prints
nothing), and `-dPXX_HEAP_DEBUG` to see whether the intermediate is being read
after free (freed bytes become `$DD` rather than a recycled neighbour's data —
`project_debug_heap_and_objtrace_flags`). Do not reason about the cause from the
symptom; this repo's expensive bugs are the ones where a plausible story went
unverified.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython covering `dict()` from a list of pairs (subscript, `len`, `in`, `.get`)
and `str.encode().decode()` round-tripping, including a non-ASCII byte if the
encoding path supports one.

---
track: N
prio: 65
type: bug
---

# `sorted(key=...)` ignores most keys, and a callable passed as a VALUE has no common ABI

```python
print(sorted(["bbb", "a", "cc"], key=len))            # CPython: ['a','cc','bbb']  pxx: ['a','bbb','cc']
print(sorted(["bbb", "a", "cc"], key=lambda s: len(s)))# CPython: ['a','cc','bbb']  pxx: ['a','bbb','cc']
f = len
print(f([1, 2, 3]))                                    # CPython: 3                pxx: SIGSEGV
g = lambda s: len(s)
print(g("abc"))                                        # CPython: 3                pxx: None
```

The sort answers with the elements' NATURAL order, so it looks correct whenever
the key order and the natural order coincide — which is how it survived. My
first attempt at this ticket's own test used `["bb","a","ccc"]`, where the two
orders agree, and reported a pass.

## Two layers, and the second is why the obvious fix does not work

**Layer 1 — `sorted` consults only one of four callable shapes.** `pyeval.pas`:

```pascal
if (key <> nil) and pyclosure_is(key) then keys.append(pyclosure_call1(key, ev))
else keys.append(ev);                      { <-- silently sorts by the element }
```

This unit's own interface note says NilPy has FOUR shapes — a bound method, a
pyeval closure, a lifted bound-fn, and a plain compiled def's address — and
"every library that accepts a callable meets all four". `sorted` checks one and
silently ignores the rest. `min`/`max` do not accept `key` at all (loud).

**Layer 2 — the other shapes have no usable Variant ABI.** ATTEMPTED and
REVERTED (commit not kept; recording the dead end so it is not retried blind):
extending the dispatch to `pyboundfn_is` and to a raw code address makes things
worse, not better.

| key shape | pinned | with the dispatch widened | CPython |
| --- | --- | --- | --- |
| `lambda p: p[1]` (interpreted) | correct | correct | correct |
| `lambda v: -v` (interpreted) | correct | correct | correct |
| `lambda s: len(s)` (LIFTED to a bound-fn) | wrong (natural order) | wrong (input order) | — |
| plain `def` returning an int | wrong | correct | — |
| plain `def` returning a **str** | wrong | **SIGSEGV** | — |
| `key=len` (a builtin) | wrong | **SIGSEGV** | — |

`TPyCallFn1` is declared `function(const a0: Variant): Variant` because "that is
what an unannotated `def f(): ...` compiles to". That is only half true: an
unannotated def's return type is INFERRED from its first `return`, so
`def k(s): return s[0]` genuinely returns an `AnsiString` and the Variant
prototype mismatches — hence the crash. A lifted lambda calling a builtin
returns a useless value for the same family of reasons.

So widening `sorted` alone converts a wrong answer into a crash for two shapes
and a different wrong answer for a third. The dispatch is not the fix; the ABI
is.

## Independent sub-bugs, each reproducible on its own

1. **A builtin as a first-class value crashes.** `f = len; f([1,2,3])` core
   dumps — on `pinned` too, so it predates all of this. `f = str` does not even
   parse.
2. **A pyeval closure that calls a builtin returns None.** `g = lambda s: len(s);
   g("abc")` → `None`. The interpreter has no `len`/`str`, and answers None
   rather than failing.
3. **A plain def handed over as a callable value has no Variant ABI** — safe for
   int/float results, corrupt for a managed-string result.

## Shape of a fix

The frontend already solves this for lambdas in one place: the lifter wraps them
so the call bridge sees a known signature. A def or builtin used as a VALUE
wants the same treatment — a wrapper with a fixed `(Variant) -> Variant` ABI
that adapts the callee's real return convention — rather than each library
routine guessing from a bare pointer. Once that exists, `sorted` can simply call
`pyvar_callv1` and every shape works, and `min`/`max`/`list.sort` get `key=` for
free.

Until then, `sorted` deliberately keeps the narrow `pyclosure_is` test: sorting
by the element is wrong, but it is not a crash.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering the table
above against CPython's own output. Pick test data where the key order and the
natural order DIFFER — otherwise the test passes without the key being called.

## Log
- 2026-07-31 — resolved, commit 4f5864fe053f4fee8eef53901419c1e1d489e45b.

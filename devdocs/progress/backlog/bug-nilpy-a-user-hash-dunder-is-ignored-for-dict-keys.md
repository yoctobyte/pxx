---
summary: "A class defining BOTH `__hash__` and `__eq__` is a legal dict key in CPython, and pxx stores it then never finds it again: `d = {k1: 'a'}; k2 in d` is False for an equal k2. The entry is silently lost — no diagnostic, and `k1 == k2` answers True right beside it."
type: bug
track: N
prio: 50
found-by: claude-AN
---

# A user `__hash__` is ignored for dict keys

- **Type:** bug (NilPy — silent wrong value) — **Track N**
- **Opened:** 2026-08-10, verifying the hash/equality consistency cases while
  closing [[bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant]].
  Confirmed pre-existing at `stable_linux_amd64/default/pinned`.

## Repro

```python
class K:
    def __init__(self, v):
        self.v = v
    def __eq__(self, o):
        return self.v == o.v
    def __hash__(self):
        return self.v

k1 = K(1)
k2 = K(1)
d = {k1: "a"}
print(k1 == k2, d[k2] if k2 in d else "miss")
```

CPython: `True a`. pxx: `True miss`.

The two halves of the same line disagree — `k1 == k2` is True (and now runs the
dunder from either operand shape), while the dict cannot find the key the
equality says it already holds.

## Distinct from the sibling ticket

[[bug-nilpy-object-dict-key-with-eq-but-no-hash-is-accepted-then-misses]] is the
class with `__eq__` and NO `__hash__` — CPython **refuses** that at the store
(`unhashable type`), so the fix there is to raise. This one defines `__hash__`,
so CPython accepts it and the program is correct Python that pxx silently loses.
Fixing the sibling by raising would NOT fix this, and fixing this must not make
the sibling's shape start working.

## Where to look

`pylib`'s `PyUserObjHash` already exists — the consistency partner of
`PyUserObjEq`, which `PyVarEq` calls — and `pyvar_hash`'s own comment says it
"mirrors PyVarEq arm-for-arm". So the machinery is present on both sides; the
question is whether the dict's lookup path reaches it, and whether the key was
hashed by IDENTITY at store time (in which case the stored bucket is
unreachable no matter what lookup computes). Check store and lookup separately
before concluding — a hash that disagrees between the two paths is silent by
construction, exactly what `project_rtti_method_table_multi_consumer_stride_landmine`
warns about for its own multi-consumer table.

## Gate

`make test-nilpy` + self-host byte-identical, with a `.npy` case covering: store
then `in` / `[]` / `.get()` with an equal-but-distinct key; two keys with the
same hash but unequal (a real collision, so the bucket chain is exercised);
mutation of the key's field after the store (CPython loses it too — match that);
and the sibling's no-`__hash__` shape still behaving as its own ticket decides.
Diffed against CPython via `tools/pydiff.py run`.

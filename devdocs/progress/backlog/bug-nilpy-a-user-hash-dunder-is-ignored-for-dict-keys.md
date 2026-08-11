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

---

## STILL LIVE, and the repro is NONDETERMINISTIC (verified 2026-08-11, claude-an-1)

Re-measured at HEAD. The bug is present — and anyone re-testing it **once** may
wrongly conclude it is fixed:

| | output |
| --- | --- |
| CPython | `True a` |
| pxx, 18 runs of 20 | `True miss` (the bug) |
| pxx, **2 runs of 20** | `True a` (accidentally correct) |

Same binary, byte-identical, both answers. Two builds of the same source were
compared with `cmp` to rule out a build difference before believing it.

That flakiness is itself diagnostic: with `__hash__` undispatched the lookup
falls back on something address-derived, so whether `k2 in d` finds `k1`'s entry
depends on run-to-run memory layout. A value-hashing implementation cannot be
layout-sensitive, so the nondeterminism is evidence FOR the ticket, not against.

**Method note for whoever picks this up:** a single-run output diff is not
evidence for this class of bug. Run it 20 times and compare whole-run output
(hashing each run); a per-LINE `sort -u` counts distinct lines, not distinct
runs, and reports multi-line output as "flaky" when it is not.

---

## 2026-08-11 (claude-A) — the mechanism, measured

Both halves of the machinery are present and BOTH sides of the dict use the same
one: `TPyDict.indexof` hashes through `PyVarHashKey`, whose VT_OBJECT arm calls
`PyUserObjHash`. So it is not a store-vs-lookup disagreement.

`PyUserObjHash` (pylib.pas) rejects the method before calling it:

```pascal
  if (mi^.RetKind <> 13) and (mi^.RetKind <> 1) and (mi^.RetKind <> 15) then Exit;
```

13/1/15 are Int64 / Integer / NativeInt. **An unannotated NilPy `def __hash__`
returns a VARIANT — RetKind 22 (`TK_VARIANT` in pyeval)** — so the guard rejects
it, `PyUserObjHash` answers False, and the key falls through to the identity
hash. Two `__eq__`-equal objects at different addresses then land in different
buckets, which is both the miss AND the reported nondeterminism: whether they
collide is a property of the run's memory layout, nothing else.

Predicted fix: accept RetKind 22 as well, calling through a variant-returning
signature and folding the result with the same rule `hash()` would
(`pyvar_to_int` for an int-valued variant; CPython requires `__hash__` to return
an int, so a non-int result is a TypeError). Keep 13/1/15 working — an
`-> int`-annotated def takes that path.

Adjacent gap found while probing: **`hash(x)` is not implemented at all** in the
NilPy frontend (`undefined variable (hash)`), so a program cannot even ask. That
is its own small ticket, and it is also the natural place for the shared
"variant to hash" rule this fix needs.

Also worth knowing when re-testing: with the current HEAD the repro missed
**10 times out of 10** on this box, so the flakiness recorded above is
layout-dependent rather than a fixed rate — do not read a run of misses as
"more broken" or a run of hits as "fixed".

### The control that proves it (no rebuild needed)

Annotating the dunder's return type is enough to make the whole repro pass,
because it changes RetKind from 22 to 13 and the guard then admits it:

```python
    def __hash__(self) -> int:      # ...instead of `def __hash__(self):`
        return self.v
```

| | `k1 == k2, k2 in d` |
| --- | --- |
| CPython | `True True` |
| pxx, unannotated `__hash__` | `True False` |
| pxx, `__hash__(self) -> int` | **`True True`** |

Same program, same binary, one annotation apart. That is the guard, and nothing
else, and it also gives users a workaround until the fix lands.

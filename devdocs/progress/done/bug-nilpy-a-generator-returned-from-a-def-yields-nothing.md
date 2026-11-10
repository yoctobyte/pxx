---
track: N
prio: 40
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "A Nil Python generator created inside a def and returned from it yields nothing: `def mk(): return gen(5)` then `list(mk())` gives [] (CPython [5, 6]), and `next(mk())` does not compile. Same on every target, on v446 and fad87004e4e8."
owner: ""
---

# A Nil Python generator returned from a def yields nothing

```python
def gen(n):
    yield n
    yield n + 1
def mk():
    return gen(5)
print(list(mk()))     # [] ; CPython [5, 6]
x = mk()
print(next(x))        # compile error: no overload of next matches these arguments
```

`g = gen(5); print(list(g))` at the same level works. A generator that is
RETURNED does not survive, because the def's return kind is not a generator. The
behaviour is the same on x86-64, i386, aarch64 and arm32.

When this is fixed, also check the str-literal argument temp in
`PyBuildGeneratorValue` (bug-nilpy-a-generator-called-with-a-str-literal-segfaults).
It is a local of the function that creates the generator, so an escaping
generator would need its slot to hold its own reference.

Related: `feature-nilpy-a-generator-as-a-first-class-value`.

## Log
- 2026-11-10 — closed: the repro above prints what python3 prints at latest 1c6f046ff4 (fixed by earlier work, commit not traced); pinned as test/test_nilpy_a_generator_returned_from_a_def.py.

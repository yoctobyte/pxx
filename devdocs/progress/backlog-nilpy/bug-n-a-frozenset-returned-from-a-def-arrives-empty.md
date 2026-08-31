---
track: N
prio: 60
type: bug
blocked-by: []
summary: "A frozenset returned from a def arrives at the caller EMPTY -- len 0, repr 'frozenset()', membership False -- no matter how it was built. set, list, dict and tuple returned from the same shape are all correct, and a frozenset that never crosses a return is correct too. Silent data loss, no crash, no error."
---

# A `frozenset` returned from a `def` arrives empty

- **Type:** bug (Nil-Python frontend) — **Track N**.
- **Filed:** 2026-08-30 by frankB, from
  [[feature-b-sweep-mimic-shims-against-cpython]] phase 2, while extending the
  `copy` differential. `copy.copy(frozenset([1,2]))` answered `frozenset()`.
- Measured at pin **v395** (`stable_linux_amd64/default/pinned`), CPython 3.12
  as the oracle. Every row below is from a run, not from reading code.

## Repro

```python
def f():
    return frozenset([1, 2, 3])

print(len(f()))       # pxx: 0        CPython: 3
print(repr(f()))      # pxx: frozenset()   CPython: frozenset({1, 2, 3})
print(1 in f())       # pxx: False    CPython: True
```

## The boundary is the RETURN, and nothing else

Four axes were varied. Only one moves the answer.

**How the frozenset was built does not matter** — all three are empty at the
caller:

| body | pxx | CPython |
| --- | --- | --- |
| `return frozenset([1,2,3])` | **0** | 3 |
| `y = frozenset([1,2,3]); return y` | **0** | 3 |
| `def f(x): return frozenset(x)` | **0** | 3 |

**The type does** — every sibling container survives the identical shape:

| body | pxx | CPython |
| --- | --- | --- |
| `return set([1,2,3])` | 3 | 3 |
| `return list([1,2,3])` | 3 | 3 |
| `return dict({...})` | 3 | 3 |
| `return tuple([1,2,3])` | 3 | 3 |

**A frozenset that never crosses a return is fine** — this is what rules out
"the constructor is broken":

| expression | pxx | CPython |
| --- | --- | --- |
| `len(frozenset([1,2,3]))` at module level | 3 | 3 |
| `def g(): y = frozenset(...); return len(frozenset(y))` | 3 | 3 |
| `def g(x): return len(frozenset(x))` — int returned | 3 | 3 |
| `def g(x): n=0;` `for _ in frozenset(x): n+=1;` `return n` | 3 | 3 |
| `frozenset(a_frozenset)`, `set(fs)`, `list(fs)`, `tuple(fs)` | 2 | 2 |

The fourth row is the sharp one: the *same call in the same function on the
same parameter* is correct when its **length** is returned and empty when the
**frozenset** is. And `isinstance` is right on every axis — `isinstance(fs,
frozenset)` True, `dict`/`list`/`set`/`tuple`/`str` all False — so this is not
a misclassification taking the wrong constructor branch.

## Why it is worth p60

It is the expensive shape, not the cheap one: **no crash, no exception, no
diagnostic.** The object that arrives is a well-formed, valid, *empty*
frozenset, so every downstream operation succeeds and answers as if the set
were genuinely empty. A membership test silently answers False; a loop over it
runs zero times; a `len` reads 0. Nothing anywhere reports a problem.

`frozenset` is the container people reach for precisely to pass a fixed set
*out* of a function — a constant table, an allow-list, a set of reserved names
— so "returned from a def" is not an edge of its use, it is close to the whole
of it. An allow-list that arrives empty fails **open or closed depending on the
caller's polarity**, and neither shows up as an error.

## What it broke, concretely

`lib/rtl/mimic_copy.py`'s `copy()` does `return frozenset(x)` for the frozenset
branch — the platonic line, and the one CPython's own docs describe. So
`copy.copy(frozenset([1,2]))` returns an empty frozenset and `== ` against the
original answers False. The shim is correct as written; per the platonic-code
rule the line stays and the ticket carries the defect.

That branch is currently unreachable from the corpus (`html5lib` copies an
attribute dict), which is the only reason this had not surfaced.

## Suggested first look

`set` works and `frozenset` does not, through an identical return path, so the
divergence is in whatever the two do *differently* on the way out of a call —
the immutability handling being the obvious candidate. If the return path
copies-on-return by rebuilding the container, a frozenset rebuilt through a
path that assumes mutability would come back empty in exactly this way. Do not
take that as the diagnosis; it is where to point the first probe.
`PXXDBG=n.locals` / `a.ir:<proc>` on the four-line repro should settle it
quickly, and the repro is small enough to read the IR of.

## Gate

`make test-nilpy` green + self-host byte-identical. A regression test wants all
five container types returned from a def in one file, because the point of the
finding is that four of them are right.

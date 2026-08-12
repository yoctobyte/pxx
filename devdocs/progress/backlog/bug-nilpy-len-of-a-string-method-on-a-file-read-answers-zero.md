---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`len(f.read().split('\\n'))` answers 1 and `len(f.read().upper())` answers 0 — as if the file were empty — while the identical expression printed, assigned, or iterated is correct. The read really happens (a following f.read() returns ''), so the string is produced and then lost on the way into len() alone"
---

# `len()` of a string method on `f.read()` answers zero

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython.

```python
with open(p) as f:                      # p holds "a\nb\nc\n"
    print(len(f.read().split("\n")))    # pxx: 1     CPython: 4
with open(p) as f:
    print(len(f.read().upper()))        # pxx: 0     CPython: 6
with open(p) as f:
    b = f.read().split("\n")
    print(len(b))                       # pxx: 4     CPython: 4  -- correct
```

Counting lines with `len(f.read().split("\n"))` is a stock idiom, and the wrong
answer (1) is exactly what an empty file would give — so it reads as "the file
was empty", not as a compiler defect.

## The boundary — only `len`, only an unbound receiver

| expression | pxx | CPython |
| --- | --- | --- |
| `len(f.read().split("\n"))` | **1** | 4 |
| `len(f.read().split())` | **0** | 3 |
| `len(f.read().upper())` | **0** | 6 |
| `len(f.read().strip())` | **0** | 5 |
| `len(f.read())` | 6 | 6 |
| `len(f.readlines())` | 3 | 3 |
| `print(f.read().split("\n"))` | `['a','b','c','']` | same |
| `repr(f.read().upper())` | `'A\nB\nC\n'` | same |
| `sum([1 for x in f.read().split("\n")])` | 4 | 4 |
| `b = f.read().split("\n"); len(b)` | 4 | 4 |
| `s = f.read(); len(s.split("\n"))` | 4 | 4 |
| `len(mk().upper())` for a user `def mk()` returning str | 3 | 3 |

So: the string method itself is right, `len` on the same value bound to a name
is right, and every other consumer of the unbound expression is right. It is
the pair — `len` **and** a string method whose receiver is `f.read()`.

## Not double evaluation — measured

```python
with open(p) as f:
    x = len(f.read().upper())
    y = f.read()
print(x, repr(y))          # pxx: 0 ''      CPython: 6 ''
```

`y` is empty in both, so the file WAS consumed exactly once: the read happened,
the method ran, and the result was lost specifically on the way into `len`. A
user def in the same position (`len(mk().upper())`) is correct, which points at
what `f.read()` yields — a variant/bytes rather than a plain AnsiString — being
handled by a `len` argument path that a NAME never takes.

## Where to look

`len`'s lowering for a call-result argument, against the receiver-shape split
this frontend already has twice over
([[project_nilpy_lvalue_vs_selector_path_must_both_know]]): a bare name and a
call result reach member access through different parsers, and `len` is the
consumer that gets the call-result form wrong. Compare what `len` receives for
`f.read().upper()` versus `s.upper()` (`PXXDBG=a.ast` on the enclosing statement
is the cheapest first look).

## Gate

A `.npy` diffed against CPython: every row of the table above, plus `len` of a
chained call on a file inside an `if`, in a comprehension, as a function
argument, and after a `readlines()` — with the bound-name controls kept in the
file so a fix cannot trade one path for the other.

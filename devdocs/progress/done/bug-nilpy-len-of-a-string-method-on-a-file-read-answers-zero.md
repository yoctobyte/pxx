---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`len(f.read().split('\\n'))` answers 1 and `len(f.read().upper())` answers 0 — as if the file were empty — while the identical expression printed, assigned, or iterated is correct. The read really happens (a following f.read() returns ''), so the string is produced and then lost on the way into len() alone"
status: done
owner: claude-AN
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

## 2026-08-12 — narrowed to `read` itself, and the receiver kind is decisive

Re-measured; the earlier "unbound receiver" framing is too broad. Everything
below is `len(<receiver>.upper())`:

| receiver | result |
| --- | --- |
| `f.read()` (a file) | **0** |
| `f.readline()` (the same file object!) | 2 — correct |
| a def returning str (`def g() -> str`) | 6 — correct |
| a def returning a VARIANT (`return lst[0]`) | 3 — correct |
| a method returning str (`C().m()`) | 6 — correct |
| a string LITERAL | 6 — correct |

So it is not "a call result", not "a managed string result", and not "an
unbound receiver": `readline()` is the same receiver shape on the same object
and is right. It is **`read` specifically**, and only under `len` — `repr`,
`print`, an assignment and a `def` parameter all render the same expression
correctly.

`type(f.read()).__name__` and `type(f.read().upper()).__name__` both answer
`str`, and `len(f.read())` alone answers 6, so the value and the tag are right
in isolation.

**The suspicion to test first:** `read` is OVERLOADED (`read()` and `read(n)`,
and the ticket family around
[[project_nilpy_open_returns_tpyfile_in_every_mode]] notes that a text `read(n)`
still returns bytes). If the `len(...)` context steers overload resolution —
Track A's resolver ranks by the argument fit, and `len` wants something
countable — a DIFFERENT `read` overload may be binding inside `len(...)` than
outside it. That would explain every row above at once, including why
`readline` (not overloaded the same way) is fine.
`PXXDBG=a.ast` on the two statements, or simply giving the overloads
distinguishable return values, decides it in one measurement.

## Gate

A `.npy` diffed against CPython: every row of the table above, plus `len` of a
chained call on a file inside an `if`, in a comprehension, as a function
argument, and after a `readlines()` — with the bound-name controls kept in the
file so a fix cannot trade one path for the other.

## 2026-08-13 — FIXED. The file really was read twice; the second read got ''

The 08-12 note's "test the overloads first" suspicion is wrong, and so is the
"not double evaluation — measured" section above. Both were reasonable readings
of the evidence and both mis-locate it.

**What happens.** `len` does not simply lower its argument: it PARSES the
argument to learn its TYPE, and for anything that is not a non-container class
it REWINDS the token position and re-parses through the ordinary overload path.
A parse has side effects — a string method on a call result queues a hidden-temp
assignment on the hoist queue — and the abandoned parse's queued statement was
never removed. So the emitted code read the file TWICE: once for the AST that
was thrown away, once for the real one, and the second read got the empty string
a consumed file returns. `len('')` is 0 and `''.split("\n")` is `['']`, i.e. 1 —
the exact two wrong answers.

That also explains every row of both boundary tables at once:

  * `readline()` is fine because it yields a variant that needs no hidden temp,
    so its trial parse queues nothing;
  * a def/method/literal receiver is fine for the same reason;
  * `len(f.read())` alone is fine — no string method, no hoist;
  * `print`/`repr`/an assignment/a comprehension are fine because none of them
    rewinds;
  * and the "the file WAS consumed exactly once" measurement was reading the
    consequence: the file is consumed by the FIRST (discarded) read, so a later
    `f.read()` sees '' either way.

**The fix** parks the hoist queue across the trial parse and drops it on the
rewind (`PyHoistPark` / `PyHoistRestore` / `PyHoistMerge` in pyparser.inc,
since parser.inc cannot see `PyHoistHead`). The arms that KEEP the trial AST
merge the parked chain back instead.

**Two siblings had it too**, found by grepping for the rewind rather than by
waiting for a bug report (`normalise-dont-special-case`'s rule): `str`/`repr`
and `hex`/`bin`/`oct` do the same trial-parse-and-rewind. Measured before the
fix: `hex(len(f.read().upper()))` answered `0x0`. All three are parked now.

### Gate

`test/test_nilpy_len_of_a_file_read.npy` + `.expected` from CPython, wired into
`make test-nilpy`: every row of both tables, the same expression under `hex`,
`str` and `repr`, `len` of a chained read in an `if` and as a call argument, the
bound-name and two-step controls, a comprehension, the def/method receivers, and
the "read exactly once" assertion. `make test-nilpy` green, `gate.sh quick`
GREEN.

## Log
- 2026-08-13 — resolved, commit 6924bb987.

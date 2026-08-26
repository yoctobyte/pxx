---
track: N
prio: 82
status: done
owner: agent-N-sorted-key
---

# sorted(key=f) segfaults when f returns a tuple containing a string

`sorted(l, key=f)` crashes when the key function returns a TUPLE one of whose
elements is a string. Sorting the same tuples directly is fine, and a key
returning a scalar or an all-int tuple is fine, so it is the key path
specifically.

```python
def q(a, i=7, s="hi"):
    return (a, i, s)
print(sorted([3, 1, 2], key=q))     # Segmentation fault
```

## Boundary, measured

Same file, only the return varied:

| key returns | result |
| --- | --- |
| `a + i` (scalar) | `[1, 2, 3]` |
| `(a, i)` (int tuple) | `[1, 2, 3]` |
| `(a, i, s)` (has a string) | **SIGSEGV** |

And sorting string-bearing tuples with NO key works:

```python
print(sorted([(3,"a"), (1,"b"), (2,"c")]))   # correct
```

So neither tuple comparison nor string comparison is broken on its own — it is
the combination with the `key=` path, which materialises its keys into a
separate list (`PyCallKey1` into `keys.append`, `compiler/builtin/pyeval.pas`
~5209) rather than comparing the elements in place. A managed string reaching
that list is the obvious suspect; measure before concluding.

## Provenance

Reproduced identically on HEAD (`e78cc5882` plus the uncommitted callable-value
signature work) and on `PXX_STABLE` (`stable_linux_amd64/default/pinned`), so it
is **pre-existing and unrelated to the signature work** — found while widening
that ticket's repro, where the first draft of the test used exactly this shape.
CPython prints `[1, 2, 3]`.

---

## Worked by agent-N-sorted-key (2026-08-26) — ALREADY FIXED, and the recorded boundary was wrong

**Verdict: fixed in the tree, by the very work it was filed beside.** No compiler
change was needed. What this session added is the measurement that proves it,
the regression test that keeps it, and the correction of a boundary that would
have sent the next reader looking at string ownership in the sort — which is not
where the bug was.

### Endpoint measurement first, no bisect

Per `devdocs/dev/debugging-playbook.md`: measure the endpoints before spending a
bisect.

| binary | `def q(a, i=7, s="hi"): return (a,i,s)` + `sorted(key=q)` |
| --- | --- |
| HEAD (`9d333f757`), self-hosted fixedpoint | `[1, 2, 3]` — **green** |
| pinned v375 (`62051f727`) | green |
| pinned v374 (`0635e2d4e`), binary + its OWN frozen `builtin/` | green |
| built from source at `9bbbbef6c` — the sha this ticket was FILED in | **SIGSEGV (rc 139)** |

So it reproduces at the sha of the ticket, and at no endpoint since. Green at
HEAD across every `-O` level (`-O0`/`-O1`/`-O2`/`-O3`), under
`-dPXX_MANAGED_STRING`, under `-dPXX_HEAP_DEBUG` (which would poison a freed
payload to `$DD` rather than let it read as a plausible neighbour) and under
`-g`, plus a heap-churn variant that allocates 200 strings before the sort. It
is fixed, not hidden by heap layout.

**The provenance line above is wrong about `PXX_STABLE`, and the way it is wrong
is worth keeping.** v374 was the pin at filing time, and v374 does *not*
reproduce — measured twice, once with the binary alone and once with its own
frozen `builtin/` tree beside it. The likely cause: a stable binary run from a
directory with no `builtin/` next to it falls back to the CWD-relative
`compiler/builtin/`, i.e. to the WORKING TREE — which at filing time carried the
uncommitted signature work. "PXX_STABLE reproduces it too" was therefore a claim
about a mixed compiler, and it is what made the ticket read as pre-existing when
it was in fact the freshly-landed feature's own hole.

### The boundary is the PARAMETER INDEX, not the string

The ticket's table varied only the RETURN, so it landed on "a tuple containing a
string". Varying the DEF instead, all against the crashing binary
(`nk/pxx_9bbbbef6c`):

| def | key body | at `9bbbbef6c` |
| --- | --- | --- |
| `q(a, i=7, s="hi")` | `return (a, i, s)` | **SIGSEGV** |
| `t(a, x=1, y=2)` | `return (a, x, y)` — **no string anywhere** | **SIGSEGV** |
| `q(a, i=7, s="hi")` | `return s` (3rd param alone) | **SIGSEGV** |
| `v(a, s="hi", i=7)` | `return (a, s, i)` | **SIGSEGV** |
| `u(a, i=7, s="hi", L=None)` | `return (a,i,s,L)` | **SIGSEGV** |
| `q(a, i, s)` — no defaults at all | `return (a, i, s)` | **SIGSEGV** (CPython: `TypeError`) |
| `q(a, i=7, s="hi")` | `return (a, i)` — 3rd param NOT read | green |
| `q(a, i=7, j=8)` | `return (a, i, "hi")` — literal string, 3rd param not read | green |
| `q(a, s="hi")` | `return (a, s)` — only 2 params | green |
| `q(a, i=7, s="hi")` | `return a` (scalar) | green |
| `lambda a, i=7, s="hi": (a,i,s)` | — | green (lambdas take the closure road) |

The string is a red herring on both arms: an all-int `t(a, x=1, y=2)` crashes,
and a string LITERAL in the tuple is fine. What decides it is whether the body
**reads the third parameter**. Garbage in slot 2 happened to be benign; garbage
in slot 3 was not. The ticket's own "safe" all-int row is the shape that never
touches slot 3 — the table was two coincidences deep.

Same mechanism, other faces, same sha:

- `min([3,1,2], key=q)` — SIGSEGV.
- `fs = [q]; fs[0](1)` — SIGSEGV.
- `map(q, [3,1,2])` — **no crash, silent wrong value**: `[(3, None, ), (1, None, ), (2, None, )]`
  where CPython says `[(3, 7, 'hi'), …]`. The dropped defaults are the same
  missing signature wearing the wrong-value hat, and per the playbook's opening
  rule that is the expensive face of it, not the crash.
- `f = q; f(1)` — green, because assignment goes through `PyMakeFuncValueFor`.

### Root cause, and why no fix was needed here

A bare def name in an ARGUMENT position (`key=q`) lowered to a plain
`AN_PROCADDR` — a code address, which carries no signature — so `PyCallKey1`'s
shape-D arm (`f1 := TPyKeyCbF1(key); f1(a0)`) entered a three-parameter body
through a one-argument pointer and slots 2..n read whatever the stack held.
Two commits closed it, both after this ticket was filed:

- **`e360f0c5c`** — `PyProcHasDefaultParam` joins the star condition, so a
  DEFAULTED callee travels as a `{code, recv}` pair like a collecting one.
- **`293d70509`** — the deeper one: `ParseFactorCore`'s bare-callable arm was a
  drifted COPY of `PyMakeFuncValueFor`'s body, and is now one line of
  delegation. Every bare def name in value position is boxed, unconditionally.
  `devdocs/dev/normalise-dont-special-case.md`, applied.

Counting the mechanisms (two is a smell): there were two roads to "a def taken
as a value", `PyMakeFuncValueFor` and `ParseFactorCore`'s copy, and only the
first was right — exactly the shape this repo keeps hitting. There is now one.
`c2c0e79e0` ("the invoker owns the callable while it runs") is a *different*
lifetime bug in the same neighbourhood and is not what fixed this: reverting its
`pyeval.pas`/`pylib.pas` hunks under a HEAD compiler leaves the repro green.

### Regression test — wired into `test-core`, not `test-nilpy`

`test/test_nilpy_key_callable_reads_every_default.npy` + `.expected`
(CPython-generated), wired into **`test-core`** so it runs in the quick tier
(`test-nilpy` does not). It pins the rule the boundary actually is — *a def
reached as a callable value enters its body at its own arity and reads its own
def-time defaults in EVERY parameter position* — over `key=`, `min`, `max`,
`map`, `filter`, `reverse=`, a lambda, a list element and a parameter, keeping
the all-int row the original boundary would have called safe as the control.
Seven of its rows are the shapes measured to SIGSEGV at `9bbbbef6c` and one is
the `map` wrong-value row, so it is a crash witness, not a smoke test.

### Neighbours: filed, not folded in

- `xs.sort(key=...)` is still a **compile error** (`TPyList.sort has no parameter
  named 'key'`) where CPython sorts in place. Already filed as
  `feature-nilpy-list-sort-inplace-key-reverse` (prio 62) — the named refusal is
  deliberate, `pylib` cannot reach `pyeval`'s `PyCallKey1`. No new ticket.
- `PyProcHasDefaultParam` (`compiler/pyforwards.inc:186`) is now **dead**: the
  only call site was the condition `293d70509` deleted, and its doc comment
  still says "see the call site in ParseFactorCore". Left in place rather than
  swept, because `bug-n-a-callable-value-reaches-a-str-parameter-and-renders-as-bound-method`
  is sitting in `working/` over the same files — a stale comment is cheaper than
  a collision. Worth deleting whenever that lock clears.

### Gate

`make compiler/pascal26` — byte-identical self-host fixedpoint, converged — plus
the new test diffed against CPython's own output, plus ~40 boundary shapes green
at HEAD. No compiler source was touched: the diff is one test, its `.expected`,
and eleven Makefile lines.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.

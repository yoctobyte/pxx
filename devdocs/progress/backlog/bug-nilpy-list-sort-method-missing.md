---
track: N
prio: 50
type: bug
---

# `list.sort(key=...)` (the in-place METHOD) is missing — `sorted()` works fine

```python
rows = [(1, 3), (2, 1), (3, 2)]
rows.sort(key=lambda r: r[1])
print(rows)
```

```
error: Nil Python: TPyList has no method sort
```

Found 2026-07-31 while re-verifying [[feature-nilpy-lambda]] (closed — real
lambda values already work). The standalone `sorted(rows, key=lambda r:
r[1])` FUNCTION already works correctly (diffed against CPython, matches
exactly) — this is specifically the in-place `.sort()` METHOD on `TPyList`
that has no implementation at all, not a lambda/key= problem.

## Shape of a fix

`sorted()`'s own implementation (pyeval.pas has a `sorted(l: TPyList; key:
Pointer = nil; reverse: Boolean = False): TPyList` per this session's
earlier reading of that file) already does the real work — an in-place
`.sort()` should be a thin wrapper: call the same comparison/key logic but
write the result back into the SAME `TPyList` instead of returning a new
one (Python's `list.sort()` returns `None` and mutates in place, unlike
`sorted()`).

## Partially fixed (this session) — plain `.sort()` only

Added `TPyList.sort` (pylib.pas) as a genuine method — no-key insertion sort
using `pyvar_gt`, mutating `Self` in place (confirmed: a second reference to
the same list object sees the sort, matching Python's identity guarantee).
Diffed against CPython for both numbers and strings; exact match.

`key=`/`reverse=` NOT done: the original "shape of a fix" assumption (thin
wrapper around `sorted()`) turned out not to work — `sorted()`'s key=
dispatch goes through `PyCallKey1`, which lives in `pyeval.pas`, and
`pyeval` `uses pylib` (not the reverse), so `pylib.pas` cannot call back
into it. A real `key=`/`reverse=` implementation needs either moving the
generic-callable-invoke primitive down into `pylib.pas` (shared by both
units) or a frontend-level rewrite of `.sort(key=...)` into a build-then-
swap sequence around the existing `sorted()` — either is more than this
pass's scope. `xs.sort(key=...)` still fails to PARSE (a compile error,
not a crash — `sort` genuinely takes no parameters today), which is the
safe direction to fail in the meantime.

## Gate

`make test-nilpy` + self-host byte-identical, plus `.sort()` with no key,
with `key=lambda`, and with `reverse=True`, diffed against CPython — and
confirm the list identity is preserved (same object, mutated) the way
Python's own `.sort()` guarantees.

## 2026-08-09 — re-measured; and the "needs a frontend rewrite" half is WRONG

State at HEAD is exactly as the partial-fix note says: `xs.sort()` works,
`xs.sort(key=...)` and `xs.sort(reverse=True)` are parse errors
(`near: rows sort key >>> lambda r`).

The blocker as stated is **real**: `sorted(l, key, reverse)` and `PyCallKey1`
are both in `pyeval.pas`, and `pyeval uses pylib`, not the reverse — so
`TPyList.sort` in `pylib.pas` genuinely cannot call up to them. Verified, not
assumed.

But the note's second option — *"a frontend-level rewrite of `.sort(key=...)`
into a build-then-swap sequence"* — overstates the work. **Keyword binding is
automatic once the callee declares the parameters.** `PyKwArgIndex`
(`pyparser.inc` ~5293) resolves `name=` against the CALLEE's declared parameter
names, which is exactly why `sorted(l, key=f, reverse=True)` already works with
no per-call special case: `sorted` declares `key: Pointer = nil; reverse:
Boolean = False`. The parse error above is not a kwarg-parsing gap at all — it
is simply that `TPyList.sort` declares no such parameters.

### Correction: `reverse=` is ALREADY DONE

Filed wrong an hour earlier in this same note and corrected by measuring it on
its own. `TPyList.sort` already declares `reverse: Boolean = False` and honours
it; the parse error in the repro above comes from the `key=` line, which aborts
the compile before the `reverse=` line is reached. Measured separately:

```
xs.sort(reverse=True)     -> [3, 2, 1]        matches CPython
ys.sort(reverse=False)    -> ['a', 'b', 'c']  matches CPython
```

(`zs.sort(True)` positionally is accepted here and rejected by CPython —
ordinary NilPy laxity, not a defect: no working CPython program can observe it.)

**So the entire remaining gap on this ticket is `key=`.**

### What `key=` actually costs

`PyCallKey1` cannot simply move down into `pylib`: it depends on
`pyclosure_is`/`pyclosure_call1` and `pyboundfn_is`/`pyboundfn_callv`, all of
which live in `pyeval.pas` because they are the closure machinery itself.

The function-pointer-hook idea (pylib holds a `PyKeyCall1Hook` that pyeval
installs) does not work as stated either: **no builtin unit has an
`initialization` section** — `grep '^initialization' compiler/builtin/*.pas` is
empty — so there is nowhere for pyeval to install it from without adding that
machinery first.

That leaves the frontend rewrite: a free `pylist_sort_inplace(l, key, reverse)`
in `pyeval.pas` (which may call both `sorted` and `TPyList`), with
`xs.sort(...)` lowered to it. Kwarg binding then comes free by the rule above.
The rewrite site is the pylib-container method call in **`parser.inc`** — Track
A shared ground — which is why it was not started this session (sole-A could not
be confirmed).

Cross-reference: [[feature-nilpy-list-sort-inplace-key-reverse]] covers the same
ground; these two should be merged or one closed as a duplicate.

## 2026-08-09 — raised to prio 50: TWO independent realistic programs hit it

Raised from 35 because it stopped being hypothetical. Writing ordinary little
programs and diffing them against CPython, `.sort(key=...)` was the ONLY gap
that came up **twice, in unrelated domains**:

- a task scheduler: `ready.sort(key=lambda t: (cost[t], t))`
- an account ledger: `accounts.sort(key=lambda x: -x.balance)`

Sorting a working list in place by a computed key is not a corner of the
language; it is how the idiom is written. Every other gap those programs hit was
one-off.

A hand-written scheduler (`ready.sort(key=lambda t: (cost[t], t))`) hit this,
which is worth recording because it settles that `.sort(key=)` is a REAL-WORLD
shape and not just an API-surface gap: sorting a work list by a computed key,
in place, is how the idiom is written.

The message is now more useful than the ticket records — `TPyList.sort has no
parameter named 'key'` rather than a parse error — because `reverse=` was
already declared. That also confirms the mechanism precisely: `PyKwArgIndex`
(pyparser.inc) resolves `key=` against the CALLEE's declared parameters, so the
whole gap is that `TPyList.sort` declares no `key`.

Which means the frontend half is free, and only the BODY is blocked: declaring
`key: Pointer = nil` would bind the argument immediately, but pylib cannot
invoke it (`PyCallKey1` and the closure machinery are in `pyeval`, which uses
pylib and not the reverse).

**Do not declare `key` without implementing it.** A declared-but-ignored `key=`
would turn today's loud, accurate compile error into a silently unsorted list —
which is strictly worse and is the failure class this project ranks highest.

Workaround remains `sorted(xs, key=...)`, which is correct today, plus an
assignment if in-place is wanted (aliases will not see it).

## 2026-08-09 — narrower than the title, and the runtime half is a 6-line job

Measured: `xs.sort()` and `xs.sort(reverse=True)` both work. Only **`key=`** is
missing, and it fails LOUDLY — "TPyList.sort has no parameter named 'key'". So
the title overstates it; this is one keyword argument, not a missing method.

**Why it is where it is.** `TPyList.sort` lives in pylib and its own comment
explains the block: a `key` is a CLOSURE, and invoking one needs `PyCallKey1`,
which lives in **pyeval — a unit that USES pylib**, so pylib cannot call it.
`reverse=` needs no callable, which is exactly why that half shipped and this
half did not.

**The runtime half is trivial and belongs in pyeval, beside `sorted`:**

```pascal
procedure pylist_sort_key(l: TPyList; key: Pointer = nil; reverse: Boolean = False);
var r: TPyList; i: Integer;
begin
  if l = nil then Exit;
  r := sorted(l, key, reverse);
  for i := 0 to r.count - 1 do l.put(i, r.at(i));
  r.Free;
end;
```

Delegating to `sorted` keeps the comparison, the key-computed-once rule and the
STABILITY in one place. In-place matters: `xs.sort()` must be visible through
every other reference to the same list, which is the whole difference from
`sorted(xs)`.

I wrote and built that, then **reverted it unlanded** rather than leave a helper
with no caller — dead code in a builtin costs every compiled program.

**What is actually left is FRONTEND routing, and that is the real work.** A
statically-typed `TPyList` receiver goes through the generic method-call arg
loop in `ParseClassRecordSelectors` (`parser.inc`, around the `PyKwArgIndex`
call), which binds keywords against the callee's declared parameters — so the
intercept has to sit BEFORE that loop, detect `key=` ahead in the argument list,
and parse the arguments itself to build `pylist_sort_key(recv, key, reverse)`.
There is no existing NilPy intercept for container methods on a STATIC receiver
to hang it on (the variant-receiver path has several; a static one has none),
which is what makes this frontend-shaped rather than runtime-shaped.

Deprioritised against silent bugs while both were open: this one names itself at
compile time and cannot produce a wrong answer.

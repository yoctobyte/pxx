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

## Recon 2026-08-09 — no re-pin needed, and the frontend hook is the real cost

### The gate is cheaper than this ticket assumes

Editing `compiler/builtin/pylib.pas` / `pyeval.pas` does **not** force
`stabilize` + `pin`. Measured on
[[bug-nilpy-a-variant-argument-binds-a-class-overload-and-is-unwrapped-unchecked]]:
`compiler/compiler.pas` uses `SysUtils, Math, BaseUnix, asmcore_*` and never
`pylib`, so a pylib change cannot move the compiler binary and the self-host
fixedpoint still converges FROM PINNED. The A != B effect belongs to the builtin
units the COMPILER links, not to `compiler/builtin/**` as a directory. So this
is ordinary per-fix-loop work.

### Where `key=` has to live, and why

`TPyList.sort` cannot take a `key`: resolving a callable needs `PyCallKey1`,
which lives in **pyeval**, and `pyeval uses pylib` — so pylib cannot call back
into it. That is the same constraint that put `sorted` in pyeval, and the
existing `sort(reverse=)` comment already records it.

So the runtime half is a **pyeval free function**, e.g.
`pylist_sort_key(l: TPyList; key: Pointer; reverse: Boolean): Variant`, sorting
in place and returning None. It can reuse `sorted`'s comparison loop directly.
That half is straightforward.

### The frontend half is the actual work

`rows.sort(key=...)` is a METHOD call on a statically TPyList receiver, so it
binds keyword arguments against `TPyList.sort`'s declared parameters and fails
with "TPyList.sort has no parameter named 'key'". It must instead be rewritten
into a call to the pyeval free function, with the receiver becoming argument 0.

The existing precedent does NOT stretch to cover it. `parser.inc` ~5521 renames
`values`→`vallist`, `keys`→`keylist`, `destroy`→`destroy_` on a typed receiver,
but that hook is guarded on `(` immediately followed by `)` — **empty argument
lists only** — and it renames a METHOD to another METHOD rather than redirecting
to a free function with a shifted receiver. Both limits have to go for `.sort`,
which is why this is not a five-line change.

Check the VARIANT receiver path at the same time (`PyParseVariantMethod`), or
`.sort(key=)` will work on a list literal and not on a list that arrived as a
list element — the split this frontend is repeatedly bitten by
([[project_nilpy_lvalue_vs_selector_path_must_both_know]]).

### Also still open, same family

[[bug-nilpy-list-sort-rejects-key-and-reverse-with-a-bare-parse-error]] in
`unfinished/` is the parse-error half of this; they should be taken together,
since the fix above resolves both.

## Re-measured 2026-08-10 at HEAD (486b0e9ec) — scope is smaller than filed

This ticket's own text above is stale: it reports `TPyList has no method sort`.
The method now **exists** and takes `reverse`. Measured against CPython:

| shape | at HEAD |
| --- | --- |
| `xs.sort(reverse=True)` | works — `[3,2,1]` |
| `sorted(ys, key=len)` | works |
| `sorted(xs, reverse=True)` | works |
| `ys.sort(key=len)` | **the only gap** |

and the diagnostic is now named and accurate, not a parse failure:

```
error: Nil Python: TPyList.sort has no parameter named 'key'
```

**The lead:** `sorted(key=)` already works, so the key-callback machinery is
built and merely is not wired to the in-place `sort` method. Start from
`sorted`'s parameter handling and give `TPyList.sort` the same `key` parameter
rather than building anything new.

## Merged in 2026-08-10

Supersedes **`bug-nilpy-list-sort-rejects-key-and-reverse-with-a-bare-parse-error`**
(was in `unfinished/`, prio 50, moved to `rejected/` as a duplicate). Both
described this one residue. This copy survived because it was the one visible to
the ranker and its title is the accurate description of what is actually left.
That ticket's analysis is preserved in `rejected/`; nothing was discarded.

## 2026-08-10 — do NOT start with the unit move; see the lambda ticket first

Tracing why `TPyList.sort` cannot take `key=` bottoms out somewhere else
entirely. The chain:

1. `PyCallKey1` (call a Python callable value) must handle a **source closure**,
   so it has to live in `pyeval`, the tree-walking interpreter.
2. Therefore every `key=`-taking builtin — `sorted`, `min`, `max`, `map`,
   `filter` — lives in `pyeval` too.
3. `pyeval uses pylib`, not the reverse. `TPyList.sort` is a method on a
   **pylib** class, so it cannot follow them up. Hence no `key=`.
4. `pyparser.inc`'s cross-unit keyword-overload fallback exists only to paper
   over the resulting split (its own comment says so).

And step 1 holds only because
[[bug-nilpy-every-lambda-is-interpreted-instead-of-compiled]] makes **every**
lambda a source closure — measured 6.9x slower per call than the same body as a
nested def, and 69x slower than CPython.

Fix that first and closures become rare (runtime-bound defaults only) instead of
the default for every lambda. The layering cleanup then has a much smaller
closure arm to carry, and this ticket becomes an ordinary parameter addition
rather than a builtin-unit refactor requiring a re-pin.

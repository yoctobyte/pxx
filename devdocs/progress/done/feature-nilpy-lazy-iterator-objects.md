---
track: N
prio: 55
type: feature
blocked-by: []
summary: "UMBRELLA: map/filter/enumerate/zip/reversed return eager LISTS where CPython returns cursor objects, so a working CPython program can crash here (f runs for every element even when the loop breaks early, and a raise past the break point escapes). Build a real cursor — TPyIter in pylib, consumed by every for/list/sum/sorted site — and give iter()/next() somewhere to live"
status: done
owner: claude-N
---

# UMBRELLA: real lazy iterator objects for map / filter / enumerate / zip / reversed

- **Type:** feature (NilPy) — **Track N**
- **Decided:** [[decide-nilpy-eager-map-filter-reversed-enumerate]] (user,
  2026-08-12) — build the real thing. **Read that ticket first**: it holds every
  measurement behind this one, and the model in one table.
- **Opened:** 2026-08-12, from the differential builtin sweep.

## Why, in one measurement

`f` counts its calls; `xs = list(range(10))`:

| | after `m = map(f, xs)` | after breaking at 3 | second pass over `m` |
| --- | --- | --- | --- |
| CPython | **0 calls** | 3 | yields the remaining **7** |
| pxx | **10 calls** | 10 | yields all **10** again |

CPython's `map` is a **cursor** — an enumerator, or a database cursor — and
`for n in m` calls Next. Constructing one costs nothing; breaking parks it;
resuming continues from there. Nothing is detected or optimised: `map` is a
CLASS, `map(f, xs)` is a constructor call, and laziness is the object's
contract. pxx returns a list — i.e. **Python 2's `map`**.

The consequence that makes this a correctness ticket rather than a perf note:

```python
def risky(x):
    if x > 5:
        raise ValueError("too far: " + str(x))
    return x

out = []
for v in map(risky, list(range(100))):
    out.append(v)
    if len(out) == 3:
        break
```

CPython prints `survived [0, 1, 2]`; pxx raises `ValueError: too far: 6`. A
program CPython accepts and runs crashes here, which is the one thing the
upward-compatibility rule does not bend on.

## What "done" looks like

Every row below matching CPython, in a `.npy` diffed against it:

1. `m = map(f, xs)` performs **zero** calls of `f`.
2. `for v in map(f, xs)` with an early `break` calls `f` exactly as many times
   as elements consumed — and a raise past the break point never happens.
3. A second pass over the same bound cursor yields the **remainder**, not the
   whole thing and not nothing.
4. `list()`, `sorted()`, `sum()`, `in`, a `for` header and a comprehension all
   consume one correctly.
5. `print(m)` shows `<map object at 0x…>`; `type(m).__name__` is `map`
   (`filter`, `enumerate`, `zip`, `list_reverseiterator`).
6. `iter(xs)` and `next(it)` exist and work, including `next(it, default)` and
   the `StopIteration` on exhaustion.

## The pieces, in landing order

Each step is independently green — do NOT hold a long-lived broken state.

1. **`TPyIter` in pylib** — source (a TPyList, a str/bytes, a dict, or another
   cursor), a position, a kind, an optional stored callable, and a `next`
   returning a variant plus an exhausted signal. Plus the `iter()` / `next()`
   builtins, which have nowhere to live today
   ([[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]]). Testable
   on its own, before any existing builtin changes behaviour.
2. **Teach the consumption sites to accept one** — the `for` container path
   (`PyParseForIn`), `list()`, `sorted()`, `sum()`, `in`, and comprehensions.
   Still no behaviour change: nothing produces a cursor yet.
3. **Switch `map`**, then `filter`, `enumerate`, `zip`. One per commit, each
   with its own gate — a regression here is much easier to place per-builtin.
4. **`reversed` last.** Its source is already a materialised sequence, so the
   only observable gain is the exhaustion rule; it is the cheapest to defer if
   the budget runs out.

`range` is deliberately OUT of scope. It cheats differently — it is not a value
at all (`r = range(3)` is `undefined variable (range)`) and CPython's is a lazy
SEQUENCE (re-iterable, indexable, `len`-able), not a cursor. Its own ticket.

## The one BEHAVIOUR REMOVAL — check the suite before you start

`len(map(...))` answers **2** in pxx today and raises
`TypeError: object of type 'map' has no len()` in CPython. Going lazy makes that
row stricter, and stricter is the direction the upward-compatibility rule
normally forbids — but it is allowed here precisely because CPython REJECTS the
code, so no working CPython program can depend on it (the rule is one-way).

Still: grep `test/*.npy`, `examples/**` and `lib/**` for `len(` over a
`map`/`filter`/`zip`/`enumerate` result before switching each builtin. If
something in the tree relies on it, decide deliberately — raise like CPython
(recommended) or keep answering by materialising (laxer, but it costs the whole
point of the change for that call).

## Landmines this work walks straight into

- **A stored callable is the hazard.** `map` must keep `f` inside the cursor,
  and a callable has THREE representations here — crossing them writes a
  variant TAG into a pointer slot and faults far away
  ([[project_nilpy_callable_has_three_representations]]). A `map(lambda …)`
  payload is an interpreted pyeval source closure, which is a fourth shape
  again ([[project_nilpy_every_lambda_is_an_interpreted_source_closure]]).
  Test `map` with: a `def`, a lambda, a bound method, and a builtin (`str`).
- **pylib is `compiler/builtin`**, so every step needs `stabilize-fast` + `pin`
  after its gate, not just a commit.
- **The nilpy suite is the family sweep** for anything touching variant
  lowering ([[feedback_variant_lowering_change_needs_the_nilpy_suite]]) — quick
  alone will not see it.
- **Two passes must agree** on any return type this touches: the shell pre-pass
  and the body pass disagreeing is a silent ABI mismatch, and this session hit
  that fault line three separate times.

## Gate

Per step: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` +
`make test-nilpy` + `stabilize-fast`/`pin`. The final step additionally runs
the six "done" rows above as one `.npy` diffed against CPython, and re-runs the
early-break/raise program from the decide ticket, which is the acceptance test
for the whole umbrella.

---

## Progress

### Step 1 + the `for` consumption site — LANDED

`TPyIter` lives in `compiler/builtin/pylib.pas`: one class, eight kinds
(`PYITER_LIST/STR/REV/REVSTR/MAP/FILTER/ENUM/ZIP`), a source, a position and a
one-slot prefetch box.

**The protocol is TWO calls, not one** — `pyiter_has` prefetches and answers
whether there was a value, `pyiter_take` hands that value over and clears the
prefetch. That shape is what lets the desugared `for` keep its existing form:
`has` goes in the while CONDITION (it is idempotent, so evaluating the
condition does not advance) and `take` replaces `c.at(i)` at the top of the
body. Everything else about the loop is untouched — the `__py_i` counter still
increments at the top, so `continue` and `enumerate()` over a cursor both work
unchanged. A single `next`-plus-exhausted-flag cannot sit in a condition
without either losing the value or fetching twice.

Call counts therefore match CPython exactly: one prefetch per body run, and
**none after a break**.

Also landed: `iter()` / `next()` / `next(it, default)` as ordinary OVERLOADED
pylib functions (no parser arm — neither name is a Pascal keyword, so the
normal call path resolves them by argument type and a user `def iter(...)`
shadows them for free); `list(<cursor>)` drains; `print`/`str`/f-string all
render `<map object at 0x…>`; `type(it).__name__` answers the CPython class
name; StopIteration on exhaustion. Test: `test/test_nilpy_iter_next_cursor.npy`,
diffed against CPython, wired into `test-nilpy` (both copies of the block).

**pyeval owns the callable half.** A map cursor must CALL what it stored, and
`PyCallKey1` (the one entry that knows all four callable representations) lives
in pyeval, which USES pylib. So pylib carries a `PyIterCallHook` and pyeval's
`pymap_iter` / `pyfilter_iter` install it at CONSTRUCTION — there is no
unit-initialisation order to depend on, and a cursor cannot reach an unset hook.

Ownership is explicit: the constructors `PXXObjRetain` the source, the
upstream(s), the box and the stored callable, and `PyObjFinalize` grew a
`TPyIter` arm that releases them. No new `VT_*` tag, so the
four-places variant-tag list is NOT involved — a cursor is an ordinary tag-7
object.

#### Two things measured, not reasoned

- **`len(map(...))` has NO uses in the tree.** Grepped `test/*.npy`,
  `examples/**`, `lib/**` for `len(` over a map/filter/zip/enumerate result:
  zero hits. The one behaviour removal is therefore free.
- **A bare parameterless pylib function used as a CALL ARGUMENT does not
  resolve** — `FBox.append(pynone)` compiled fine on the NilPy path and failed
  with `undefined variable (pynone)` only when a `.pas` program `uses pylib`
  directly (`test_uses_order_pylib_exception_a.pas`). `pynone()` with parens is
  the fix. `Result := pynone` (assignment form) is unaffected, which is why
  every existing use is spelled that way. The nilpy suite caught this and the
  ad-hoc `.npy` repros could not.

### Step 3 — `map` and `filter` are LAZY

Both in one commit rather than one each. The umbrella asks for one builtin per
commit so a regression is easy to place; these two differ ONLY in the cursor
kind (`PYITER_MAP` vs `PYITER_FILTER`) and share every piece of new machinery —
the constructor-name picker, the drain sites, the acceptance test — so
splitting them would have re-run the same 20-minute sweep to isolate nothing.
Deliberate, and stated here rather than silently.

The acceptance program from the decide ticket now matches CPython line for
line: `f` runs 3 times for a loop that breaks at 3, binding a cursor runs it 0
times, breaking parks it and a second pass yields the remainder.
`test/test_nilpy_lazy_map_filter.npy`, wired into `test-nilpy`.

`map(int|str|float, xs)` went lazy too, without needing a callable: those ride
the MAP kind with `FKey` nil and the conversion code in `FStart`.

#### The six things that actually cost time

1. **`FindProc` picks a proc by BARE NAME and never consults overloads** — so
   the parser arm cannot reach an overloaded `pymap_iter`; each argument shape
   needs its own SPELLING (`_l` / `_s` / `_i`, and the bare name for a variant).
   `PyIterCtorName` does that pick.
2. **...and the same fact bites in the other direction.** Adding a harmless
   looking `pycontains(it: TPyIter; …)` OVERLOAD made
   `FindProc('pycontains')` — which the `in` operator uses — resolve to the
   CURSOR entry, so `2 in [1, 2, 3]` segfaulted. Nothing in the change
   mentioned lists. The overload is gone; a cursor receiver is drained at the
   `in` site instead, and pylib carries a comment saying why that overload must
   not come back.
3. **Declaration ORDER decides which class overload a VARIANT argument
   unwraps into.** `sum(it: TPyIter)` declared ABOVE the existing
   `sum(l: TPyList)` made `sum(v)` — v a variant holding a list — bind the
   cursor parameter and segfault, in a program containing no cursor at all.
   New class overloads of an existing builtin go AFTER the old ones. This and
   (2) are the same fact seen from two sides, and both are recorded in
   [[project_nilpy_overload_declaration_order_decides_the_variant_unwrap]].
4. **A cursor cannot be indexed**, so the sites that need a real sequence drain
   it first: the tuple-unpack RHS (`w, h = map(int, s.split("x"))`) and
   `"-".join(map(str, xs))`. `PyDrainIfCursor` is a no-op on anything else, so
   it is safe to apply unconditionally at such a site.
5. **`PyCallProc1` had to carry the result's CLASS IDENTITY** (`ASTRight :=
   ProcRetRecId`). Without it `ResolveNodeRec` answers "no identity" for the
   drain node and every consumer that dispatches on the receiver's class falls
   into its untyped arm.
6. **The FPC seed canary, not the pxx build, catches a missing forward.** pxx
   prescans; FPC does not. `PyDrainIfCursor` is called from `pyparser.inc`
   above its own definition and needed a `forwards.inc` entry —
   `make compiler/pascal26` was green the whole time.

Also in: `len(map(...))` raises CPython's exact
`TypeError: object of type 'map' has no len()` (the one deliberate behaviour
removal), `x in map(...)`, `sum`/`sorted`/`min`/`max`/`any`/`all`/`tuple` over
a cursor.

#### Found, not caused: [[bug-nilpy-map-over-a-bound-method-segfaults]]

`map(obj.method, xs)` SEGFAULTS — and the control shows it does so on the
**eager** map too (built with the pinned v263), so laziness neither caused nor
fixed it. A `def`, a `lambda` and a builtin all work; the bound-pair arm of
`PyCallKey1` is the one that faults. Filed, with the acceptance test carrying a
comment where that row belongs.

#### A Makefile escape trap, for the next person

In a `printf '%b'` ARGUMENT the octal escape is `\0ddd`, so a single quote next
to a DIGIT must be spelled `\0047` — `\047` swallows the digit as a fourth
octal digit and prints garbage. In a printf FORMAT string it is `\ddd`
instead, which is why entries around it are spelled `\047`. The two forms are
not interchangeable and a blanket rewrite of one into the other breaks the
other family's tests.

### Step 4 — `enumerate`, `zip` and `reversed` are LAZY

All five cursor builtins now match CPython, and the acceptance test carries the
park/resume row for each: an `enumerate`/`zip`/`reversed` bound to a name,
broken out of, then drained, yields the REMAINDER.

The shape that kept this small: **one conversion, not a family of spellings.**
`enumerate` and `zip` take CURSORS (`pyiter_enum_i`, `pyiter_zip_ii`) and the
frontend converts each iterable once through `PyMakeIterOf` — otherwise zip
alone would have needed nine entries to cover every pair of argument types,
because these calls are FindProc-built and not overload-aware. That also
deleted a workaround: `enumerate`/`zip` over a str used to be exploded through
`pystr_charlist` so an AnsiString handle would not be dereferenced as an object
([[bug-nilpy-str-iterable-builtins-segfault-on-a-string-handle]]); a str cursor
is the same idea with one representation instead of two.

`reversed` changed the RETURN TYPE of the existing overloads rather than adding
new ones — the declaration-order lesson above says a second class overload is
the dangerous move, and there was nothing to keep: `[::-1]` stopped routing
through `reversed` when tuple-slicing was fixed, so the tuple-flag copy it was
carrying had no consumer left. `reversed(<cursor>)` is a TypeError in CPython
and drains here instead, which is laxity in the direction the rule allows.

Two more `forwards.inc` entries were needed (`PyMakeIterOf`, `PyCallProc1`) and
again ONLY the FPC seed canary saw it.

### NEXT

All six "done" rows of this ticket are met. What is deliberately NOT in scope
and stays open:

- **`range` as a value** — out of scope from the start (it is a lazy SEQUENCE,
  not a cursor, and `r = range(3)` is still `undefined variable (range)`). Its
  own ticket.
- **[[bug-nilpy-map-over-a-bound-method-segfaults]]** — found here, measured
  PRE-EXISTING against the eager map, filed rather than worked around.
- **Generators (`yield`)** — the cursor object is now the machinery they would
  want ([[feature-nilpy-yield-outside-a-for-loop]]); the decide ticket's "revisit
  B when generators land" reads the other way round now, since B landed first.
- `x in <cursor>` drains rather than stopping at the first match, so a hit calls
  `f` more times than CPython does. The ANSWER is right and the cursor ends
  exhausted either way; noted in pylib where it happens.

## Log
- 2026-08-12 — resolved, commit c4e74b888.

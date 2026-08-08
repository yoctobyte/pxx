# NilPy: where the language deliberately differs from CPython

Divergences that are **chosen**, not bugs. Each one here has been measured
against CPython and left as it is on purpose. Anything not in this file that
differs from CPython is a bug — file it.

The rule this list is written against: **a program CPython accepts must behave
the same under pxx.** Every entry below is allowed to differ only for programs
CPython itself rejects, or in a way no accepting program can observe.

---

## Mutating a dict while iterating it is not detected

*Decided 2026-08-04 (Rene). See `decide-nilpy-dict-mutation-during-iteration`.*

`for k in d` iterates a **snapshot of the keys** taken at loop entry (the
lowering rewrites it to iterate `d.keylist()`), so the loop cannot observe a
concurrent mutation at all. CPython raises
`RuntimeError: dictionary changed size during iteration`.

Measured, all three shapes:

| the loop body… | pxx | CPython |
| --- | --- | --- |
| **inserts** a key | completes, iterating the entry-time keys | `RuntimeError` |
| **deletes** a key, never reads it again | completes; the deleted key is still VISITED | `RuntimeError` |
| **deletes** a key, then reads it | `KeyError` | `RuntimeError` |

Only the third row is "the same failure with a different message". The first two
complete silently, and the second can hand the body a key that no longer exists —
so do not describe this as "you still get an error".

**Why this is acceptable:** every program that can tell the difference is one
CPython rejects outright. No working Python program is affected. And the failure
that does occur (row three) is a catchable `KeyError` at the point of use — not
garbage, not memory unsafety, not a wrong value silently returned.

**The cost of matching CPython** is a modification counter on `TPyDict` bumped on
every insert and delete and checked once per iteration — i.e. a per-iteration
cost on every dict loop in every program, paid to reject programs that are
already relying on undefined-ish behaviour.

**A `--strict-python` mode that raises is a recorded future option**, not a
rejected one: the cost above is only acceptable because it is opt-out, so making
it opt-IN is the natural shape if the differential sweeps ever want parity.

### Precedent, stated accurately

Permissive map iteration is a normal language choice, but **no one else
snapshots**, and that is where pxx is most permissive:

- **Go** — the spec explicitly permits mutation during `range` over a map: an
  entry removed before being reached **will not be produced**, and an entry added
  may or may not be. Deliberate and documented; the closest philosophical match.
- **JavaScript `Map`** — iteration is **live**: entries added during iteration
  are visited, deleted ones are not.
- **C# `Dictionary`** and **Java `HashMap`** are the strict ones — they throw
  (`InvalidOperationException` / `ConcurrentModificationException`). C# is
  therefore *not* an example of the permissive camp, despite being an easy one to
  reach for.

pxx differs from Go and JS in the same direction for the same reason: because it
snapshots, it **does** produce a removed key. That is the one behaviour worth
naming explicitly when explaining this to anyone.

---

## Iterating a LIST is live — and this is NOT a divergence

Worth stating precisely because the dict rule above invites the wrong
generalisation: **list iteration matches CPython exactly.** Both are index-based
and live. Measured:

| the loop body… | pxx | CPython |
| --- | --- | --- |
| `append`s | 7 iterations, final len 7 | 7 iterations, final len 7 |
| `pop`s | 2 iterations, final len 2 | 2 iterations, final len 2 |

So CPython is itself asymmetric — live lists, raising dicts — and pxx matches it
on the list half. Do not "fix" the list to be a snapshot for consistency with the
dict; that would introduce a divergence where there is none.

`test/test_nilpy_iterate_live_list.npy` pins the list half;
`test/test_nilpy_dict_mutation_during_iteration.npy` pins the dict half.

---

## A tuple is mutable

*Decided 2026-08-06 (Rene), while triaging what was almost filed as a bug.*

A NilPy tuple is built as a `TPyList` and nothing marks it read-only, so every
mutating operation CPython refuses on a tuple succeeds here:

| expression | CPython | pxx |
| --- | --- | --- |
| `t[0] = 9` | `TypeError` | succeeds |
| `t.append(4)` | `AttributeError` | succeeds |
| `del t[0]` | `TypeError` | succeeds |

Everything else about a tuple is already CPython-exact: `type(t).__name__`,
`isinstance(t, tuple)`, indexing, slicing, iteration, `len`, `==`, `+`,
unpacking, and use as a dict key.

**This is not a bug**, and the reasoning generalises past tuples:

> If code works on CPython, it must work on NilPy. NilPy is *upward compatible*
> with the reference implementation. Doing something you shouldn't do, and
> having it still work under NilPy, is a language feature — not a defect.
>
> — Rene, 2026-08-06

No working CPython program mutates a tuple, so no working CPython program can
observe this. Enforcing immutability would reject nothing anyone legitimately
writes and would put a check on every store. The same call was made in the
Pascal dialect for restrictions that were historic rather than necessary — see
`../progress/backlog/meta-dialect-extensions-and-fpc-strict.md`, which is the
Pascal-side charter for exactly this trade.

**The half that IS a bug** is the TYPE tag, because a program CPython accepts
*can* observe it: `isinstance(t, list)` answers True for a tuple (and for a
set), so `flatten([[1,2], (3,4), 5])` returns `[1, 2, (3, 4), 5]` under CPython
and `[1, 2, 3, 4, 5]` here. Filed as
`bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance`. The split
between these two halves — lax mutation is fine, a wrong type answer is not — is
the cleanest worked example of the rule on this page.

---

## Set ITERATION ORDER is insertion order — and this is NOT a divergence

*Measured 2026-08-06, after a set started printing with braces and its order
became visible.*

pxx iterates and prints a set in **insertion** order, so `{3, 1, 2}` prints
`{3, 1, 2}` where CPython prints `{1, 2, 3}`. That looks like a divergence and
is not one, for a reason worth writing down rather than re-deriving:

**The language does not specify an order.** A `set` is defined as an *unordered*
collection of distinct hashable objects; iteration order is an implementation
detail of the hash table, not part of the contract.

**And CPython is not even self-consistent.** String hashing is randomised per
process by default (PEP 456, on since 3.3), so CPython's own set order changes
between runs of the same program:

```
$ PYTHONHASHSEED=0 python3 -c 'print({"alpha","beta","gamma","delta"})'
{'alpha', 'delta', 'beta', 'gamma'}
$ PYTHONHASHSEED=1 python3 -c 'print({"alpha","beta","gamma","delta"})'
{'beta', 'delta', 'gamma', 'alpha'}
$ PYTHONHASHSEED=2 python3 -c 'print({"alpha","beta","gamma","delta"})'
{'delta', 'gamma', 'alpha', 'beta'}
```

Small integers only look stable because CPython's `hash(n)` **is** `n` — an
artifact of the hash function, not a promise.

So a working CPython program **cannot** depend on set order; one that did would
already be broken under CPython. Under the upward-compatibility rule at the top
of this page, insertion order is therefore fully conforming, and pxx's answer is
if anything the more useful one (deterministic, reproducible across runs).

**Do not "fix" this to match CPython's output.** Chasing it would mean
reproducing CPython's hash function and its per-process randomisation — copying
an implementation detail that CPython itself does not guarantee, to make a
diff-based comparison look tidier. Any test that pins a set's order must sort it
(`sorted(s)`), exactly as it must under CPython.

The genuinely open set questions — whether `[1] - [2]` should raise — remain in
`../progress/backlog/decide-nilpy-set-as-a-distinct-type-or-a-list.md`. Ordering
is not among them.

## Keyword-only parameters are not enforced (decided 2026-08-08)

CPython marks some builtin parameters keyword-only — the bare `*` in
`list.sort(*, key=None, reverse=False)`, `sorted(iterable, /, *, key=None,
reverse=False)`, `min(arg, *args, key=None)`. Those may be passed by name and
only by name.

pxx implements these as ordinary Pascal routines with defaulted parameters, and a
Pascal parameter list has no notion of keyword-only, so the positional spelling
is **accepted**:

```python
sorted(xs, len)        # pxx: works.  CPython: TypeError
min(words, len)        # pxx: 'a'.    CPython: TypeError
```

**This is a divergence, not a defect.** The NilPy rule is forward compatibility
only: everything CPython accepts must work here, and accepting more is a
language feature. A pxx-only spelling fails loudly on CPython, so the cost is
deferred discovery of a portability issue, never a wrong answer.

### Why it does not endanger forward compatibility

`min`/`max` are the case worth knowing, because their second POSITIONAL slot is
another value (`*args`), not `key`. Binding it to `key` would silently change the
meaning of `min(a, b)` — valid, ordinary CPython. It does not: pxx disambiguates
on **callability**, so a callable second argument is `key` and anything else is
another value.

Verified at HEAD against the CPython oracle: `min(3, 5)`, `min(3, 5, 1)`,
`min([1,2], [1,3])`, `max([1,2], [1,3])`, `min("apple", "banana")` and
`min(words, key=len)` all agree. Only `min(words, len)` differs, and CPython
refuses that outright.

Limit of the heuristic, for the record: an object that is both callable and
orderable, passed as a second value, would take the `key` reading here and the
value reading in CPython.

### If portability checking is ever wanted

It becomes a `--strict-python`-style per-feature flag, like `--strict-case` and
`--strict-overload`. The default stays lax; see
`decide-nilpy-builtin-keyword-only-parameters`.

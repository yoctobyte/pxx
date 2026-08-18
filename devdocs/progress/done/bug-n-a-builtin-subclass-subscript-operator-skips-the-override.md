---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`c[k]` / `c[k] = v` on a subclass of `dict`/`list` goes straight to pylib's fetch/store and NEVER calls the subclass's `__getitem__` / `__setitem__`. The METHOD spelling (`c.__getitem__(k)`) dispatches correctly, and a plain user class declaring `__getitem__` dispatches correctly — it is only the builtin-subclass + operator combination. Silent wrong behaviour: the override runs zero times and nothing says so."
status: done
owner: frank2-7e
---

# A builtin subclass's subscript override is skipped by the operator form

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e while landing
  [[bug-n-a-builtin-types-method-cannot-be-called-unbound]].
- **Measured at:** HEAD + that fix, self-host fixedpoint build. Differential
  against CPython 3.12.

## Repro

```python
class C(dict):
    def __getitem__(self, k):
        print("GET")
        return dict.__getitem__(self, k)
    def __setitem__(self, k, v):
        print("SET")
        dict.__setitem__(self, k, v)

c = C()
c["a"] = 1            # CPython: SET     — NilPy: (nothing)
print(c["a"])         # CPython: GET / 1 — NilPy: 1
c.__setitem__("b", 2) # CPython: SET     — NilPy: SET      <- the method spelling is fine
print(c.__getitem__("b"))
```

| | CPython | NilPy (HEAD) |
| --- | --- | --- |
| `c["a"] = 1` | `SET` | *silent* |
| `c["a"]` | `GET`, `1` | `1` |
| `c.__setitem__(...)` | `SET` | `SET` |

So the dispatch machinery works; the OPERATOR does not reach it.

## Why it is this shape

Same family as the feature that created it. Before
[[feature-nilpy-subclass-a-builtin-type]] a `dict` subclass was not a container
to the frontend at all, so the subscript went down the user-class arm — which
DOES look for `__getitem__` (`parser.inc`, the `FindUMeth(ci, '__getitem__')`
sites around the chained-base and subscript paths). Widening "is this a
container?" from identity to kind was correct and is what made `len`/`in`/slice
work, but it also handed these instances to the CONTAINER subscript path, which
lowers straight to pylib's `fetch`/`store` (dict) and `at`/`put` (list) and
never asks whether the receiver's class overrides the protocol.

This is the failure mode the ticket family keeps producing: **two mechanisms
serve one concept** (a user-class subscript arm that consults `__getitem__`, a
container arm that does not), so a value that is BOTH gets whichever arm is
tested first. `devdocs/dev/normalise-dont-special-case.md`.

## Shape of the fix

The container subscript arm should, when the static class of the receiver is a
USER subclass of a pylib container (not the container itself), look for an
override with `FindUMeth(ci, '__getitem__' / '__setitem__')` and call it,
falling through to the direct fetch/store otherwise. The base class itself must
keep the direct lowering — that is the whole point of `dict.__getitem__` being
aliased to `fetch` and is what stops an override from recursing into itself.
Grep the sibling before closing: `__delitem__`, `__len__`, `__contains__` and
`__iter__` are the same question and probably the same answer.

## Priority note

Filed at the same prio as its sibling rather than higher despite being a
silent-wrong-value bug, because the shapes that hit it are exactly the shapes
that could not COMPILE until today — so no working program has been getting a
wrong answer from it. That changes the moment a builtin subclass with an
overridden subscript lands in a real corpus (html5lib's `MethodDispatcher` is
precisely one), which is when this should be re-rated.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, plus the repro
above matching CPython line for line, and
`test/test_nilpy_subclass_a_builtin_type.npy` /
`test/test_nilpy_unbound_builtin_method.npy` unchanged.

---

## Resolution (2026-08-18, frank2-7e)

**Measured the surface first, rather than fixing the two members the ticket
named.** A differential probe against CPython 3.12 with all seven protocol
members overridden on a `dict` subclass:

| member | override called? |
| --- | --- |
| `__getitem__` | NO |
| `__setitem__` | NO |
| `__len__` | NO |
| `__contains__` | NO — and it answered **False**, a wrong value, not a no-op |
| `__delitem__` | NO |
| `__iter__` | yes |
| `__bool__` | yes |

So it was **five** sites, not the two in the repro, and the coordinator's read
was right: the gates historically tested one member of a family and the
siblings went unlooked-at. `__contains__` was the worst of them — `"q" in c`
answered False without entering the method written for it.

**One predicate, applied at every container fast-path**, rather than five local
patches: `PyRecOverridesDunder(rec, dunder)` — "does this rec's own class
DECLARE this member, i.e. is there an override the fast path is about to step
over". Keyed on `PyRecIsPylibOwnClass` (the DECLARING UNIT) rather than a class
name list, the same reasoning that predicate already carries: pylib's own
containers declare no dunders at all, so it is False for them by construction
and cannot rot as pylib grows a container.

Sites:

- **subscript read/write** (`parser.inc`, the default-indexed-property arm) —
  the root of it. pylib's containers declare `Items[]`, a subclass INHERITS it,
  and the property arm is tested before the `__getitem__`/`__setitem__` arm. Now
  drops `pri` when `PySubscriptWantsDunder` says the class's own member owns
  this subscript, handing it to the arm a plain user class already takes rather
  than growing a second dunder path beside it. Decided **per operation**, not
  per class: `RO` in the test overrides the read only and its writes still reach
  the base, which is what CPython does and what html5lib's `MethodDispatcher`
  needs.
- **`len()`** (`parser.inc`) — the container test is by KIND, so a subclass
  matched it and never reached the `__len__` arm.
- **`in`** (`pyparser.inc`, `PyParseIsCmp`) — computed once as `ovrIn` and
  applied to every arm of the chain, so the answer cannot differ between the
  dict, range and bytes fast paths.
- **`del c[k]`** — needed no edit of its own. It reads back the node the
  subscript grammar built, so once the read lowers to a `__getitem__` call the
  existing user-class arm finds `__delitem__` on its own. The sibling rule
  paying off rather than costing.
- **`PyPylibMethodAlias`** — added `__delitem__`, so the delegation spelling
  `dict.__delitem__(self, k)` resolves (`remove` on TPyDict; `pop_at`, NOT
  `remove`, on TPyList — `list.remove` takes a VALUE, and aliasing to it would
  have deleted the wrong element without a word).

**A segfault found on the way, and fixed here.** `list.__len__(self)` crashed.
The unbound-call path passes the receiver POSITIONALLY, so `self` is already
inside `CountCallArgsAhead`, and it handed that count to
`FindUMethOverloadAhead`, which adds one for the implicit Self — an arity one
too high. Invisible while every name had a single overload (the name-only
`FindUMeth` fallback rescued it) and a silent wrong pick the moment one did not:
it selected `TPyList.count(const v: Variant)` and passed `self` as the VALUE,
with no receiver. Now tries the self-inclusive arity first under `PyExprMode`,
dropping a match that turns out to be static (a static takes no positional
self). This also corrects `A.m(self, x)` against an overload set, which was
picking the wrong body for the same reason.

**Deliberately NOT closed, both named rather than left to be rediscovered:**

- **Augmented** — `c[k] += 1` on a class reaching subscripting through the
  dunders is a NAMED compile-time refusal, which is the dunder arm's own
  pre-existing limitation; what changed is its reach. Routing an augmented
  subscript there when either member is declared was the deliberate choice: the
  alternative was `c[k] += 1` silently calling pylib's `store()` while the plain
  `c[k]` beside it called the override. Filed as
  [[bug-n-an-augmented-subscript-on-a-dunder-class-is-refused]] with the desugar
  the property arm above it already implements.
- **Slices** — `l[0:2]` keeps the container lowering; slices are diverted above
  this site by `PyIsSliceBase`. CPython passes a slice OBJECT to `__getitem__`
  and this frontend has no such value, so the honest options were to refuse
  slicing on any overriding class (breaks working code and an existing test) or
  to invent an argument. Recorded in
  `devdocs/dev/nilpy-semantics-divergences.md` as a genuine divergence, not
  filed, because closing it needs a slice value.

**Verified:** `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.
`test/test_nilpy_builtin_subclass_dunder_dispatch.npy` is **byte-identical to
CPython 3.12's output** on the same file, and pins all five members on a `dict`
AND a `list` subclass, the read-only-override shape, and the plain containers
unchanged. Wired into `test-nilpy` and `test-core`.
`test_nilpy_subclass_a_builtin_type.npy` and
`test_nilpy_unbound_builtin_method.npy` re-diffed against CPython: unchanged.

## Log
- 2026-08-18 — resolved, commit 2087aa018.

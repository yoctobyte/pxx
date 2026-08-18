---
track: N
prio: 55
type: feature
blocked-by: []
summary: "`class X(list)` / `(dict)` / `(str)` is refused with `Nil Python: unknown base class <t>` — a NilPy class can only inherit from another user class or `object`. Base-class resolution goes through FindUClassNonRecord, a USER-class lookup, and the builtin types are not user classes. 4 corpus files, one of them imported by 10 others."
status: done
owner: frank2-7e
---

# Subclassing a builtin type (`list`, `dict`, `str`) is unsupported

- **Type:** feature (object model) — **Track N** (`compiler/pyparser.inc`)
- **Found:** 2026-08-18 by frank2-7e, from the corpus ladder A/B in
  [[feature-nilpy-thirdparty-libraries-as-targets]].
- **Measured at:** HEAD `c7974b6af`, self-host fixedpoint build.

## Measured surface

Each line its own one-file program:

| declaration | result |
| --- | --- |
| `class X:` | OK |
| `class X(object):` | OK |
| `class X(list):` | `Nil Python: unknown base class list` |
| `class X(dict):` | `Nil Python: unknown base class dict` |
| `class X(str):` | `Nil Python: unknown base class str` |

So it is **every** builtin type, not one missing name — `object` and the
implicit base are the whole working surface.

## Why

`pyparser.inc:31164` resolves a base class with `FindUClassNonRecord` (with the
`Exception` and qualified-unit cases handled just above). That is a **user-class**
lookup, and NilPy's builtin types are not user classes — `list` is the runtime's
list, not a row in the class table. Nothing is looked up and it errors.

So this is not a missing name to register: it needs the builtin types reachable
as base classes and their behaviour inherited (a subclass of `dict` must still BE
a dict to everything that consumes one). Sized like the other object-model items
in this backlog rather than a lookup fix — the same shape of finding as the
recon on [[feature-nilpy-yield-outside-a-for-loop]], where the title implied a
narrow context bug and the mechanism was "unimplemented".

## Corpus evidence (why it is worth ranking, not the size)

Ladder corpora only — html5lib / tinycss2 / webencodings, 67 `.py` files:

| site | file | reach |
| --- | --- | --- |
| `class MethodDispatcher(dict)` | `html5lib/_utils.py` | **imported by 10 files** |
| `class BoundMethodDispatcher(Mapping)` | `html5lib/_utils.py` | same file |
| `class ActiveFormattingElements(list)` | `html5lib/treebuilders/base.py` | imported by 5 |
| `class Trie(Mapping)` | `html5lib/_trie/_base.py` | imported by 1 |
| `class DefaultDict(dict)` | `html5lib/tests/support.py` | test-only |

`_utils.py` is the one that matters: it is behind 10 of html5lib's 52 files, so
this sits on the same kind of chokepoint `constants.py` did for the `digits`
wall. `Mapping` (2 sites) is `collections.abc` rather than a builtin, so it may
be a shim question instead — worth separating when this is picked up.

## Gate

`make test-nilpy` + self-host byte-identical. Plus: a `list` subclass that
appends and indexes, a `dict` subclass that is read through `[]` and `in`, and
each passed to a function annotated with the builtin type.

## Reranked 40 -> 55 by the coordinator, 2026-08-18 — it gates a chokepoint

Verified independently before reranking: `class X(list)`, `(dict)` and `(str)` all fail
with `unknown base class`, while `object` compiles. So this is the whole builtin
surface, as filed, not one missing name.

The rerank is not about the row size. `html5lib/_utils.py` carries
`MethodDispatcher(dict)` and is imported by **10 of html5lib's 52 files** — the same
chokepoint shape `constants.py` had for the `digits` wall, which is the row that
actually moved on 2026-08-18. So this blocks a file that blocks ten, and it pairs with
[[feature-b-module-shims-for-the-html5lib-corpus]]: `_utils.py` needs both, and scoring
it as shim-only would under-count it.

## RESOLVED 2026-08-18 (frank2-7e, Track A+N) — the name was the easy half

Landed green. **Smaller than the "dedicated pass" sizing I gave it when I filed
it** — that sizing was mine and it was wrong, so correcting it here rather than
letting it stand.

### What the probe found, before any change

`class X(TPyList)` — pylib's own class, spelled its own way — **already
compiled**. So the object model supports descending from a container; only the
NAME was unreachable. That one measurement is what re-sized the ticket, and it
took a minute.

After mapping the builtin names onto the pylib classes, most of the surface
worked immediately through ordinary inheritance: `[]` store and read, `.get`,
`.items`, `.keys`, iteration, `repr`, `sorted`, `sum`, and the subclass's own
methods. What did NOT work was the interesting part.

### The real mechanism: an IDENTITY test standing in for a KIND question

The frontend asked, in a dozen places:

```pascal
if rec <> REC_UCLASS_BASE + FindUClass('TPyList') then ...
```

That is "is this EXACTLY TPyList", and the question it stands for is "is this a
list". The two were the same thing while nothing could descend from a pylib
container, and `class MethodDispatcher(dict)` makes them different — in the
worst direction, because the **runtime was right all along**: `pylen_v` tests
`o is TPyDict`, and Pascal's `is` answers through the chain. So the object WAS a
dict and only the compiler disagreed:

| on a subclass | before |
| --- | --- |
| `len(d)` | `TypeError: argument is not a container` |
| `x in d` | same |
| `x[1:3]` | `this value cannot be sliced` |
| `for k in d` | `pylib (get) not loaded` |

Two predicates now answer identity-or-inheritance — `PyRecIsCls(rec, 'TPyList')`
and `PyCiIsA(ci, target)` — and every one of those sites asks one of them. That
is the point of doing it this way rather than adding four subclass cases: a new
pylib container, or a new consumer, cannot re-introduce the identity test by
copying a neighbour (`devdocs/dev/normalise-dont-special-case.md`).

### Refusals that stayed refusals, and now say why

`class S(str)` is still refused, but no longer as "unknown base class":

```
error: Nil Python: str cannot be subclassed — it is a value type here, not a
class (list, dict, set, bytes can be)
```

`str`/`int`/`float`/`tuple` are values, not classes with a vtable, so there is
nothing to descend from — that is a property of the representation, not a
missing registration, and the message now says so instead of sending the reader
hunting.

A class that is NOT a container still raises on `len()` — pinned in the test,
because the obvious way to break this fix is to widen the container arms until
every instance is measurable.

### Corpus: ONTO the next wall

Reported past-vs-onto. **Zero files compile.**

| file | pinned v351 | HEAD |
| --- | --- | --- |
| `html5lib/treebuilders/base.py` | `unknown base class list` | `:134 undefined variable (list)` |
| `html5lib/_utils.py` | `no unit named xml_etree_elementtree` | unchanged — **the shim wall comes first** |

Two things worth stating plainly against this ticket's own ranking argument:

1. **`_utils.py` did not move at all.** It is behind a module-shim wall before it
   ever reaches its `MethodDispatcher(dict)`, so the "blocks a file that blocks
   ten" case for THIS ticket only pays out once
   [[feature-b-module-shims-for-the-html5lib-corpus]] lands. The rerank reasoning
   was sound; the sequencing was not visible from the first-wall table.
2. **`base.py` moved onto `list.append(self, node)`** — a builtin's method called
   unbound. Filed as
   [[bug-n-a-builtin-types-method-cannot-be-called-unbound]] with both corpus
   sites, and deliberately NOT folded in here: it needs class-NAME resolution
   widened across four sites in the shared `parser.inc`, which is a separate
   capability and not something to bolt onto a green change late in a session.

`Mapping` (2 sites) is `collections.abc`, a shim question, exactly as this ticket
predicted — untouched.

### A note on the gate that caught the one mistake

The helpers were first defined next to their users and the **FPC seed canary**
failed: PXX tolerates a call before the definition, FPC does not. Moving them
ahead of first use was the whole fix. Recording it because that canary is the
only gate step that catches this class, and it caught it in one run.

### Verified

len, index, slice, membership, iteration and an own method on BOTH a `list` and
a `dict` subclass; `bytes` as a base; the plain containers unchanged (list, dict,
str, bytes and range slices, membership, len); a non-container class still
raising TypeError. All match CPython.

**Test:** `test/test_nilpy_subclass_a_builtin_type.npy`, wired into BOTH
`test-nilpy` and `test-core`.

**Gate:** `make compiler/pascal26` fixedpoint (converged after 1 round) +
`tools/gate.sh quick` GREEN. Shared file `parser.inc` touched (one `len` arm) —
A/P slot declared to the coordinator and held for the job.

## Log
- 2026-08-18 — resolved, commit PENDING-COMMIT.

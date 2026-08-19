---
track: B
prio: 68
type: feature
blocked-by: [bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view, feature-nilpy-for-loop-getitem-protocol-fallback]
summary: "`unknown base class Mapping` is now the single biggest remaining wall on the third-party ladder — 7 html5lib files, up from 3, and all four etree files landed on it. No shim exists: lib/rtl has collections.pas (no Mapping) and no mimic_collections_abc.py. Needs Mapping / MutableMapping / MutableSet as ordinary classes. BLOCKED on two N bugs that break exactly the mixin methods an ABC is made of."
status: working
owner: frankonpiler-etree
---

# `collections.abc`: Mapping and MutableMapping as a shim

- **Track B** (module shim — same family as the ElementTree tree model that just landed).
- **Filed by the coordinator 2026-08-19** off frank3's ladder re-measurement. It had **no
  ticket**, which is why this is filed the moment it was named: the biggest lever on the
  corpus being visible only in a worker's report is the exact failure this repo keeps
  recording (`measuring a thing is not filing it`).

## Why it is the top lever now

Measured by frank3 at pin **v353** (`256183a5f52c`): the ladder moved **6/48 → 10/48**,
and the whole of that belongs to v353's generator series, which removed the **18-file
`yield` wall** outright. With `yield` gone, the new top wall in html5lib is:

    unknown base class Mapping     7 files (was 3)

All four `xml.etree` files are on it, having moved past `unknown base class dict` — which
`feature-nilpy-subclass-a-builtin-type` fixed and is in `done/`. So this is that ticket's
unfinished neighbour, and nothing else on the ladder is close to it in size.

## What is actually missing — measured, not assumed

```
library_candidates/html5lib/html5lib/_utils.py:6        from collections.abc import Mapping
                            _trie/_base.py:4            from collections.abc import Mapping
                            treebuilders/dom.py:5       from collections.abc import MutableMapping
                            treebuilders/etree_lxml.py:20  from collections.abc import MutableMapping
```

Each sits in a `try/except ImportError` with a `from collections import Mapping` fallback
(the pre-3.3 spelling), so **both spellings must resolve** or the fallback masks the real
error.

On our side: `lib/rtl/collections.pas` exists and exports **no** `Mapping`; there is no
`mimic_collections_abc.py`; `pyparser.inc:32949` knows the root name `collections`.

## THE BLOCKER, and it is not optional

`Mapping` is an ABC whose value is its **mixin methods** — `__contains__`, `keys`,
`items`, `values`, `get`, `__eq__`, `__ne__` — all derived from a subclass's
`__getitem__`, `__len__` and `__iter__`. A shim that cannot provide those is a shim that
compiles and answers wrong.

frank3 filed two bugs in the same session that hit **exactly** that surface, and did not
connect them to this wall:

1. **[[bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view]]** (N, p55) —
   `keys()` / `items()` / `values()` on a user class through an **untyped receiver** is
   dispatched as a dict view: segfault, or a garbage 6-element list of empty strings for a
   2-key dict. Precisely three names; every other method dispatches fine. **These are three
   of the seven methods `Mapping` exists to provide.**
2. **[[feature-nilpy-for-loop-getitem-protocol-fallback]]** (N, p25) — a class with
   `__len__` + `__getitem__` and no `__iter__`: `for x in obj` is a compile error naming an
   unrelated internal (`pylib (count) not loaded`), and `list(obj)` **compiles and returns
   `[]`**. The silent empty list is the worse half. **That is the iteration half of the
   same protocol.**

**Recommend reranking (2) — p25 badly understates it.** It was filed as a standalone
protocol gap; it is a prerequisite for the corpus's top wall. That is the
title-names-the-encounter pattern again: neither ticket's own framing shows it is
load-bearing for 7 files.

## Shape

Ordinary NilPy classes in `lib/rtl/mimic_collections_abc.py`, with `Mapping`,
`MutableMapping`, and `MutableSet` if the corpus asks (check — do not add speculatively).
Re-export from `collections` too, so the `except ImportError` fallback path resolves.

Follow the ElementTree precedent for the omit-vs-refuse call: **omit** what nothing
imports rather than shipping a refusing stub, and verify against CPython with a
differential rather than by reading. frank3's ElementTree write-up records two cases where
the plausible reading was wrong and shipped, and only the differential caught it —
`find("*")` matching comments, and `path.split("/")` shredding a `{http://…}` URI.

## 2026-08-19 (frank3-etree) — both blockers are DONE and neither is in the PIN

Not blocked on work any more; blocked on delivery. Measured, not inferred:

| | landed | in pin v355 (`264489d47360`, 10:34)? |
| --- | --- | --- |
| [[bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view]] | `810f219c3`, 13:01 | **no** |
| [[feature-nilpy-for-loop-getitem-protocol-fallback]] | `6905d6fd0`, 13:07 | **no** |

`git merge-base --is-ancestor` says no for both, and the pinned binary confirms
it rather than the git history alone: on v355 `for x in s` over a
`__getitem__`+`__len__` class is still `pylib (count) not loaded`, and
`keys()`/`items()`/`values()` through an untyped receiver still misbehave.

Track B builds with `$(PXX_STABLE)`, so this cannot start until a pin carries
both. Building it on v355 would not fail loudly — `Mapping` is an ABC whose whole
value is the mixin methods derived from `__getitem__`/`__len__`/`__iter__`, i.e.
exactly those two fixes, so the shim would compile and answer wrong. "Fixed at
HEAD" and "unblocked for B" are two claims and only the second one starts this.

Escalated to the coordinator, since a pin holds the repo-wide lock. Leave
`blocked-by` as it is: the tickets named there are the right ones, they are just
in `done/` ahead of the pin, and rewriting the field would hide why the ticket is
waiting.

## Gate

Track B's: build with `$(PXX_STABLE)`, `make lib-test`. Then **re-run
`tools/nilpy_ladder.py` and report past-a-wall separately from onto-the-next-wall, naming
the pin sha** — a single after-the-fact run would credit this shim with whatever else
landed, which is the trap frank3 avoided by measuring the same-pin pair first.

## 2026-08-19 (frank3-etree) — DONE, and it moves zero corpus files. Both facts matter.

Built on pin **v356** (`2bb09afb0cff` at `5b93f1155a7b`), which carries both
blockers — verified on the pinned binary itself, not from git history: `for x in
s` iterates, and `keys()`/`items()`/`values()` through an untyped receiver
dispatch correctly.

### Shipped

- `lib/rtl/mimic_collections_abc.py` — `Mapping` (`get`, `__contains__`, `keys`,
  `items`, `values` as mixins over an abstract `__getitem__`/`__len__`/`__iter__`)
  and `MutableMapping` (`__setitem__`, `__delitem__`, `pop`, `popitem`, `clear`,
  `update`, `setdefault`).
- `test/lib_mimic_collections_abc.npy` — 47 assertions, wired into `make lib-test`.

**`MutableSet` omitted, by measurement.** Every `collections` import across
html5lib / tinycss2 / webencodings / reportlab asks only for `Mapping`,
`MutableMapping`, `OrderedDict`, `deque`, `namedtuple`. Following the ElementTree
precedent: omit what nothing imports rather than ship a refusing stub.

`__eq__`/`__ne__` are also omitted, and that one is **named in the shim's
docstring** rather than silently dropped, because their absence is the kind that
answers wrong instead of failing — two equal mappings compare unequal by identity.

### The differential is falsifiable

Byte-identical output under CPython and pxx. Before believing that zero, five
deliberate perturbations of the shim were each caught:

| perturbation | caught as |
| --- | --- |
| `items()` uses `self[k]` instead of `self.__getitem__(k)` | `KeyError: 'a'` |
| drop the dead `return iter([])` after the abstract `raise` | `TypeError: iter() returned non-iterator` |
| `get` always returns the default | 4 assertions fail |
| `pop` returns `None` where it should raise | 2 fail |
| `clear` returns without draining | 3 fail |

### Past-a-wall vs onto-the-next-wall — reported separately, as asked

**Past a wall: ZERO files. The ladder does not move at all on pin v356.** All 7
files on `unknown base class Mapping` still stop there, re-measured file by file
with the shim in place.

The reason is a *different* bug, and it is the one that actually blocks the
corpus: the corpus writes `from collections.abc import Mapping`, and that spelling
never reaches the shim. `PyImportRootIsConsumedOnly`
(`compiler/pyparser.inc:33003`) tests only the **root** of a dotted from-import
and has `collections` on its consume-and-ignore list, so the whole submodule is
swallowed and binds nothing. `import collections.abc as cabc` does reach the shim
— that asymmetry is what localises it. Filed as
[[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]]
(N, p62).

So the honest split is: **this ticket delivered a correct component that is
currently unreachable.** To show the component is load-bearing rather than merely
green, the 7 files were re-compiled with their import spelling mechanically
rewritten to `import collections.abc as _cabc` + `Mapping = _cabc.Mapping`:

| file | with the corpus's own spelling | with the spelling rewritten |
| --- | --- | --- |
| `_trie/_base.py` | `unknown base class Mapping` | **OK — compiles clean** |
| `_utils.py` | `unknown base class Mapping` | `undefined variable (__name__)` |
| `serializer.py` | `unknown base class Mapping` | `undefined variable (__name__)` |
| `treebuilders/__init__.py` | `unknown base class Mapping` | `undefined variable (__name__)` |
| `treewalkers/__init__.py` | `unknown base class Mapping` | `undefined variable (__name__)` |

One file all the way through and four onto a later, unrelated wall. The shim is
correct; one compiler bug stands between it and those files.

### Track N bugs found and filed

Building an ABC mixin is an unusually good probe for dispatch, because the whole
pattern is a base class calling *down*. Five filed, all measured on pinned v356:

- [[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]]
  (p62) — **the one that unblocks the 7 files.**
- [[bug-n-a-mixin-cannot-iterate-self-and-an-abstract-iter-breaks-its-overrides]]
  (p55) — `for k in self` in a base method binds to the base `__iter__`.
- [[bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override]] (p55) —
  `self[k]` in a base method binds statically; `self.__getitem__(k)` does not.
  Sibling arm of the already-resolved
  `bug-n-a-builtin-subclass-subscript-operator-skips-the-override`, which fixed
  only the builtin-base half of the same double case. **Third sighting of one root
  cause** — `root-cause-over-microfix.md` calls that a design flaw, not three bugs.
- [[bug-n-hasattr-through-an-untyped-parameter-is-always-false]] (p55) — sharper
  than it first looked: not dict-specific, `hasattr` answers False for
  *everything* through a dynamic receiver, including `hasattr(a_list, 'append')`.
- [[bug-n-isinstance-does-not-accept-a-qualified-class-name]] (p45) —
  `isinstance(x, mod.Cls)` is a compile error.

Four workarounds registered in `devdocs/dev/track-b-workarounds.md` with their
revert conditions.

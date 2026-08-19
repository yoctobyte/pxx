---
track: B
prio: 68
type: feature
blocked-by: [bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view, feature-nilpy-for-loop-getitem-protocol-fallback]
summary: "`unknown base class Mapping` is now the single biggest remaining wall on the third-party ladder — 7 html5lib files, up from 3, and all four etree files landed on it. No shim exists: lib/rtl has collections.pas (no Mapping) and no mimic_collections_abc.py. Needs Mapping / MutableMapping / MutableSet as ordinary classes. BLOCKED on two N bugs that break exactly the mixin methods an ABC is made of."
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

## Gate

Track B's: build with `$(PXX_STABLE)`, `make lib-test`. Then **re-run
`tools/nilpy_ladder.py` and report past-a-wall separately from onto-the-next-wall, naming
the pin sha** — a single after-the-fact run would credit this shim with whatever else
landed, which is the trap frank3 avoided by measuring the same-pin pair first.

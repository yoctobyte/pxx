---
track: N
prio: 40
type: feature
blocked-by: []
summary: "`class X(list)` / `(dict)` / `(str)` is refused with `Nil Python: unknown base class <t>` — a NilPy class can only inherit from another user class or `object`. Base-class resolution goes through FindUClassNonRecord, a USER-class lookup, and the builtin types are not user classes. 4 corpus files, one of them imported by 10 others."
status: backlog
owner: unassigned
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

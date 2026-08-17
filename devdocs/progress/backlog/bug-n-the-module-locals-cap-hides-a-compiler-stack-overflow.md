---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`PY_MAX_LOCALS = 512` is too low for real modules — html5lib's constants.py needs between 513 and 1024 — but raising it is NOT the fix on its own: with the cap raised, two html5lib files SEGFAULT the compiler (exit 139, no diagnostic) at the default 8 MB stack. `ulimit -s unlimited` turns the crash back into a diagnostic, so it is a stack overflow the cap has been masking."
status: backlog
owner: unassigned
---

# The module-locals cap hides a compiler stack overflow

- **Type:** bug (resource limit + robustness) — **Track N**
  (`compiler/pyparser.inc`), with a Track A flavour: the failure mode is a
  compiler crash on valid input.
- **Found:** 2026-08-17 by frank2, measuring what was behind the wall cleared by
  [[bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails]].
- **Measured at:** HEAD `65d26b24c`, native self-hosted builds (three of them —
  the shipped 512, and probe binaries at 1024 and 8192). Not `pinned`.

## The two facts, in the order they must be fixed

**1. The cap is too low.** `PY_MAX_LOCALS = 512` (`compiler/pyparser.inc:21`)
backs five arrays and is enforced at `pyparser.inc:26116` with
`Nil Python: too many inferred module locals`. `html5lib/constants.py` — which
most of html5lib imports — trips it. Bracketed by building the compiler twice:
it compiles cleanly at 1024, so the requirement is **between 513 and 1024**.

**2. Raising it exposes a segfault.** With the cap at 1024 *or* 8192 (identical
behaviour, so this is not a size artefact of the arrays themselves):

```
html5lib/filters/whitespace.py     → Segmentation fault (core dumped), rc=139
html5lib/treewalkers/__init__.py   → Segmentation fault (core dumped), rc=139
```

No diagnostic, no line number. It is a **stack overflow**, not a wild pointer —
under `ulimit -s unlimited` both files stop crashing and report an ordinary
compile error instead ([[bug-n-a-qualified-base-class-named-like-its-subclass-is-rejected-as-self-inheritance]]).
The default stack here is 8 MB. `constants.py` compiled *alone* at 1024 does not
crash, so the depth comes from the nested-import path, not from that one module.

So the shipped 512 has been acting as an accidental depth limiter. **Do not land
a bare constant bump**: it converts a clear diagnostic into a silent crash on
exactly the files it is meant to unblock, which is a regression in kind even
though it unblocks more input.

## Suggested order

1. Find and bound the recursion (the nested-import parse path is where the depth
   comes from — `constants.py` alone is fine, `whitespace.py`, which imports it
   through `..constants`, is not). Either make it iterative or give it an
   explicit depth guard that *reports* rather than crashes.
2. Then raise the cap. 1024 clears the measured requirement; a grown/dynamic
   table would be better than another fixed number, and there are five arrays
   dimensioned by it (`PyLocals`, `PyModuleLocals`, `PyPhantomNames`,
   `PyUnkBindNames`, `PyTopTargets`), so the memory cost is not free.

## Gate

`html5lib/constants.py` compiles; `filters/whitespace.py` and
`treewalkers/__init__.py` produce a *diagnostic or success*, never exit 139, at
the DEFAULT stack limit (do not gate under `ulimit -s unlimited` — that is the
instrument that proved the cause, not the fix). Plus `make test-nilpy` green +
self-host fixedpoint.

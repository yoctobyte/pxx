---
slug: feature-n-a-pxx-marker-module-so-an-application-can-ask-whether-it-is-under-pxx
title: a pxx marker module, so an application can ask whether it is under pxx
summary: "OWNER'S DECISION 2026-09-20 (relayed by frankuser, secondhand): instead of an application detecting pxx by `try: import ctypes` FAILING, give pxx a special named module that exists ONLY under pxx, so the application asks the question directly. His words: *\"we could have PXX have a special named module (could be mostly empty) that would indicate if we are compiling under pxx. that way, we don't need the 'ctypes import' hack - and can safely implement a ctypes. small change in the lekkerzeilen and TSP application, and allows us to move forward.\"* The mechanism already exists and needs no new machinery: NilPy resolves `try: import X / except ImportError:` at COMPILE time, and CPython takes the except arm naturally because the module is not there. UNBLOCKS 10 of TSP's 20 remaining failures (3 direct ctypes imports, 7 downstream of tsp/platform/__init__.py:89) and lekkerzeilen's backend selection, WITHOUT pxx pretending ctypes is absent -- and it leaves room to implement a real ctypes later. TWO ENGINEERING POINTS ARE OPEN, both raised to the owner and neither settled: the module's NAME (a claimable name like `pxx` answers TRUE under CPython for anyone who pip-installs a package of that name; a dunder-ish name such as `__pxx__` cannot be claimed -- and `sys.implementation.name` is where a CPython programmer looks first, with the module as the cheap check), and its CONTENT (he said \"mostly empty\"; a seat proposed target, pointer size and version, since applications have no way to ask today -- last week's `sys.maxsize` bug was that same gap)."
track: N
type: feature
prio: 80
status: backlog
owner: ""
blocked-by: []
---

# A pxx marker module

## Why this shape and not a ctypes shim

The hazard the owner's inversion removes, measured 2026-09-19 and recorded in
`devdocs/dev/resume-after-reboot-2026-09-19.md`: both lekkerzeilen and TSP select
their backend with `try: import ctypes / except ImportError: _pxx`, which NilPy
resolves at COMPILE time. **The moment an importable `mimic_ctypes` exists, both
applications flip onto the CPython arm silently**, because the import SUCCEEDING is
the signal. That is why a partial ctypes is worse than none.

Asking the question directly inverts it: the application tests for pxx, not for the
absence of ctypes, so implementing ctypes later cannot flip anything.

## What is measured and what is not

- **Measured**: NilPy resolves a guarded import at compile time (the mechanism this
  relies on) — same mechanism recorded in the hazard above.
- **Measured**: 10 of TSP's 20 remaining compile failures are ctypes-gated
  (`0dfa0d78d` census, frankh-c0).
- **NOT measured**: whether the guarded-import arm selection binds correctly when the
  live arm is lexically FIRST. CLAUDE.md records a first-wins alias-table defect of
  exactly this shape (`uses`/import order). **Whoever takes this must write the
  fixture with the marker import in BOTH positions**, and with and without an `else:`.

## Open, for the owner

1. **Name.** `pxx` is claimable on PyPI; `__pxx__` is not. Also consider
   `sys.implementation.name`, which is the first place a CPython programmer looks.
2. **Content.** "Mostly empty" versus carrying target, pointer size and version.

## Not pxx's to change

The application-side edits in lekkerzeilen and TSP belong to those repos' seats.

## ADDENDUM 2026-09-20 — the superglobal variant, and why the import wins

The owner offered a simpler shape and then settled it himself (relayed by
frankuser, secondhand): *"it could even be simpler by having pxx define a
'superglobal' that we could just test.. (so just - if __HAS_PXX is not none: )..
but the import hack is fine too, just make the name a bit more magic (dunders, or
some other special chars)"*.

**The import idiom with a dunder-ish name is the shape to build.** A bare
superglobal is NOT symmetric: under CPython an undefined name raises `NameError`
rather than evaluating to None, so `if __HAS_PXX is not None:` CRASHES there and the
application needs a `try/except NameError` anyway — uglier than the import, and
linters and type checkers flag the undefined name besides.
`if globals().get('__PXX__'):` would work on both sides, **but that depends on NilPy
supporting `globals()`, which is UNVERIFIED — do not quote it as available without
measuring it.**

**The exact spelling is still the owner's.** He asked for dunders or other special
characters; `__pxx__` was a seat's suggestion, not his instruction.

**The property that makes this cheap on the application side, and the reason he
likes it:** pxx resolves the import at COMPILE time, so the CPython arm is never
compiled. The application keeps its ctypes code exactly where it is and **pxx does
not need to understand any of it.**

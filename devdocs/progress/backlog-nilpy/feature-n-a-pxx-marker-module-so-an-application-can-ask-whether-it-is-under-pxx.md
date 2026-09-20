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

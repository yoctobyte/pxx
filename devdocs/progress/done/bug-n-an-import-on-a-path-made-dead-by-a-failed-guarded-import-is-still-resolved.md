---
slug: bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved
track: N
type: bug
prio: 80
status: done
owner: frankB
created: 2026-09-10
found-by: frankuser
tags: [nilpy, imports, lekkerzeilen, portability]
blocked-by: []
summary: "FIXED 2026-09-10 (compiler `ca814b0aabcc`). THE TICKET'S STATED CAUSE WAS WRONG AND THAT IS THE USEFUL PART: it read as a dominance problem -- imports resolved on a path a failed guard made unreachable -- and there is no reachability machinery to be wrong. `PyPreScanImports` is a flat token walk that resolves EVERY import in the file, exempting only those lexically inside a `try:`, so `if False: import X`, an import after a `return` and an import in a function nobody calls all fail identically to live code. Four probes killed the dominance reading before any code was opened. Repaired the ONE unreachable shape that has a consumer and a decidable answer: the tail after a fallback-import try whose guarded import MISSED and whose handler EXITS. Both layers needed it -- the prescan resolves first, the parser would resolve the tail afterwards anyway. The other three shapes are deliberately untouched (no consumer, and no answer without a call graph). NOT the last wall on platform/__init__.py: behind it is bug-n-a-module-bound-by-an-import-is-not-a-value, and modules-compiling delta is 0, predicted before the re-run and matched."
---

# Measured 2026-09-10, compiler `c3e38195d910`, tree `416a8771c`

```
platform/_pxx.py       COMPILES
platform/__init__.py   pascal26:8: error: import: no unit named ctypes and no shim mimic_ctypes
```

`_select_backend()` reads, in substance:

```python
try:
    import ctypes
except ImportError:
    from . import _pxx
    return _pxx, "pxx"
from . import _ctypes_backend      # <- dead under pxx, resolved anyway
return _ctypes_backend, "ctypes"
```

`_ctypes_backend.py:8` is `import ctypes`, unguarded — correctly so, because
nothing reaches it unless ctypes exists.

**Note the reported line: 8, in a file whose line 8 is RST prose.** That is
`bug-n-an-error-inside-an-imported-module-is-reported-with-that-modules-line-number-and-no-file-name`
showing up while diagnosing this one; it cost frankB ten minutes testing whether
a docstring was parsed as an import. Read the line number as belonging to the
imported module.

# What works, so the boundary is stated rather than guessed

| shape | result |
| --- | --- |
| `try: import ctypes / except ImportError: ctypes = None` | **compiles, runs** |
| `from . import _fallback` | **compiles, runs** |
| the fall-through above | `no unit named ctypes` |

So this is not "guarded imports do not work". It is: **the compiler resolves
imports on a path the failed guard has already made unreachable.**

# Why it is 80

It is the last wall on the seam ENTRY of the prio-90 target, and the backend it
selects already compiles. Nothing above `platform/` can run until `__init__.py`
does — and the fix is not a `mimic_ctypes`, which is settled: the seam exists
precisely so ctypes is never needed under pxx, and shimming it would make the
seam pointless.

The wider population is the reason it is not merely a lekkerzeilen ticket:
`try: import X / except ImportError: <use fallback>` is the standard Python
portability idiom, and any program using it to avoid a module we do not have
hits this.

# Resolution — 2026-09-10, frankB

## The stated cause did not survive four probes, and they cost nothing

Run BEFORE opening any code, against `ca814b0aabcc`'s predecessor:

| shape | result |
| --- | --- |
| `def never(): return 1; import ctypes` | **error** |
| `def never(): import ctypes` (never called) | **error** |
| `if False: import ctypes` | **error** |
| `try: import ctypes / except ImportError: ctypes = None` | compiles |

`if False:` failing identically to live code says reachability is **not
consulted at all**. There is no dominance analysis here to be wrong, so a fix
aimed at one would have gone looking for machinery that does not exist.

## The mechanism

`PyPreScanImports` walks the whole token stream and resolves every import it
meets, with exactly one exemption — lexically inside a `try:`, where the module
may legitimately be absent. That is the entire reachability model.

## What was repaired, and why only this

The tail after a fallback-import `try` whose guarded import **missed** and whose
handler **exits**. Both halves are decidable on the spot: the miss because the
prescan is what resolves it, the exit because `PyBlockEndsInExit` reads the
handler's tokens. No call graph.

`PyParseFallbackImportTry` already skipped the rest of the TRY BLOCK on a miss —
the argument was accepted one indent level in and simply stopped there.

**Two layers, both required.** The prescan runs first and would report the
missing module before the parser was reached; the parser would resolve the tail
afterwards even if the prescan skipped it. Fixing either alone changes nothing,
which is why the first attempt (parser only) measured as no change at all.

The other three shapes stay refused: no consumer in any corpus, and no answer
without a call graph. A widening with no caller is a second path that stays
broken.

## Controls, measured

- **Positive**: the PINNED compiler answers `pascal26:27: error: import: no unit
  named also_no_such_module_9f2a` on the new test — the dead tail import in
  `select()`. Red pre-fix at the exact line the fix is about.
- **Must still fail (a)**: a handler that FALLS OFF ITS END leaves the tail
  reachable; its missing import is still an error. Asserted in the Makefile.
- **Must still fail (b)**: when the guarded import RESOLVES, the tail is the
  live branch; its missing import is still an error. This is the one a skip
  keyed on the `try` statement rather than on the MISS would have swallowed.
- **Oracle**: the test's guarded module is a name NEITHER runtime has, so
  CPython takes the same branch and the row is a real cross-check rather than an
  assertion of our divergence. Byte-identical, six rows including a nested case.

## What it did NOT do

The ticket called this the last wall on `platform/__init__.py`. It was not.
Behind it is `bug-n-a-module-bound-by-an-import-is-not-a-value` — the seam
returns its backend AS a value and then reads members through the variable.
**Modules-compiling delta: 0**, written down before the re-census and matched.
A first-failure census cannot see the wall behind the one it reports, so "the
last wall" was never a claim the instrument could support.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

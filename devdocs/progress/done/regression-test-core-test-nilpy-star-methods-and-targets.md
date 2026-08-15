---
prio: 70
status: done
owner: claude-A-N
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_star_methods_and_targets.npy red at 89dae725b972 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T10:08:51Z
- **Test source:** test/test_nilpy_star_methods_and_targets.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_star_methods_and_targets.npy'` at 89dae725b972d7019a20e6df61cbc18c6c9862c6

## Range
bad `89dae725b972`, last good `4c9da77f9368`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:76: error: invalid symbol in lea
(tail)
pascal26:76: error: invalid symbol in lea
  near:   main    >>>  unit builtinheap 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED — an in-`try` import inside a def outlived its own symbols

Nothing to do with star methods or unpack targets. The test's row 1 is

```python
def imports_inside(t):
    try:
        import math
    except ImportError:
        return 0.0
    return 2.5
```

and that alone is a seven-line repro. Reproduced on `pinned` too, so the
watcher's 12-commit range is where it became reachable, not where it was
introduced.

### Measured, not reasoned

`--strict-ir`'s "invalid symbol in lea" says only that an `IR_LEA` names a
symbol index outside the table. A one-line probe on the verifier
(`IRVerifyIntStr`, the local int→string the diagnostic already carries) gave the
numbers: **sym=439, SymCount=400** — 39 symbols had been rolled back after
something recorded index 439. That is the exact failure class `parser.inc`
~25411 already documents for a different construct: *an index recorded into a
pending global initializer, then discarded by `SymRollbackTo`, leaving a
dangling `IR_LEA` in main.*

Varying the shape pinned the boundary to one construct:

| shape | result |
| --- | --- |
| module-level `try: import math` | ok |
| `def` + bare `import math` (leading, mid-body, under `if`, under `for`) | ok |
| `def` + `try/except` with no import | ok |
| **`def` + `try: import math`** | **fails** |

### Cause

`PyPreScanImports` pulls every import to MODULE scope before any body is
parsed — and deliberately **skipped** those inside a `try:`, because that is the
fallback-import idiom and the module may be absent. So a `try`-guarded import
inside a def was the one import parsed *in the def's own symbol range*: the unit
allocated its globals there, the def's `SymRollbackTo(savedSC)` discarded them,
and the pending global initializers the unit had queued (typed constants, via
`CompilePendingGlobalInits` in main) outlived their symbols.

`PyParseFallbackImportTry` already guards the sibling half of this — it resets
`PyHoistHead` so "a stray IR_LEA of a rolled-back temp" cannot escape a skipped
block. That fix covered the hoisted STATEMENTS an import run leaves behind and
not the queued INITIALIZERS, which is the other thing it leaves behind. Same
defect, second carrier — [[normalise-dont-special-case]]'s "if you fix one arm
of a double case, grep for the sibling".

### Fix

Pull the in-`try` import in the pre-pass like every other one, with the resolver
in **soft mode** (`SoftUnitResolve`, the machinery `PyParseFallbackImportTry`
already uses). A module that IS present is then loaded at module scope, below
every def's `savedSC`, where the rollback cannot reach it. A module that is
ABSENT is missed silently and left entirely to the block parse, which decides
the branch exactly as before — so the fallback idiom is untouched.

This is the root-cause fix rather than the microfix: rolling the pending
initializers back instead would have left the unit's typed constants reading
zero, which is the bug `bug-nilpy-typed-const-import-reads-zero` fixed.

### Verified

`test_nilpy_star_methods_and_targets.npy` matches CPython byte for byte (the
Makefile's assertion is a live `python3` diff). The soft-import contract is
intact — a genuinely missing module still prints `fallback`, at module level and
inside a def. Whole import family green on HEAD and, as the control, identical
on `pinned` except for this test: `dotted_import`, `--no-shims`,
`fallback_import`, `fallback_import_try_wins`, `import_in_body`.
`tools/gate.sh quick` GREEN.
- 2026-08-15 — resolved, commit PENDING-COMMIT.

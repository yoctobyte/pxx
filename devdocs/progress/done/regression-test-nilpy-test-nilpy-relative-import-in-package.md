---
prio: 70
track: N
status: done
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 37 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_relative_import_in_package.npy red at ee62e6dc0582 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T18:57:16Z
- **Test source:** test/test_nilpy_relative_import_in_package.npy test/test_nilpy_relative_import_in_package.expected +1

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_relative_import_in_package.npy'` at ee62e6dc0582f6a018102c4e1d1d9a083d7e4f32

## Range
bad `ee62e6dc0582`, last good `154d1aa3fba6`, 76 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:10: error: undefined variable (RENAMED)
(tail)
pascal26:10: error: undefined variable (RENAMED)
  near: A   U  RENAMED >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Resolution (2026-08-29)

**Track N confirmed, not guessed** — the defect is in `compiler/pyparser.inc`
(`PyParseImportRun`), squarely a frontend file. Verified before claiming, as the
auto-filed track-guess banner asks.

### Cause

`__init__.py` reaches its siblings like every real package does:

```python
from .two import A, B          # queues A and B
from . import two
from .two import A as RENAMED  # source A is now "queued"
```

Inside a pulled module **every** from-imported name is queued, aliased or not —
that queue entry *is* the re-export binding. The self-capture guard (added so
that `from M import f as g, g as f` does not resolve the second item's source
`g` onto the `g` the first item just allocated) scanned the **whole** queue.
But `PyParseImportRun` loops over every consecutive `from` statement and the
queue accumulates across all of them, so statement 3's source `A` matched the
entry statement 1 had queued. `aliasRealSym` was cleared, `RENAMED` was never
allocated, and line 10 (`U = RENAMED + 100`) failed with
`undefined variable (RENAMED)`.

### Fix

The claim the guard makes is about **one** from-import statement, so the scan is
now per-statement. It matches on a **statement stamp** — the statement's own
token index, carried in a new `PyImpAliasStmt` parallel to the existing
`PyImpAliasSym`/`PyImpAliasSrc`.

### Why a stamp and not the obvious queue index

The cheap version — `aliasStmtBase := PyImpAliasCount` at statement start, scan
from there — **passes this ticket's test and silently breaks the guard**, which
is why it is worth recording. `PyParseImportRun` is visited **twice** over the
same tokens (measured with a temporary `PXXDBG` probe: four visits for a
two-item import). A statement's first-pass entries therefore sit *below* the
count its second pass starts from, so the second pass scans an empty range and
the guard stops firing altogether.

Measured three-way, PRE / index-base / stamp, against compilers built from the
**same base** so the comparison is honest (`pinned` is many commits behind HEAD
and is not a control for this):

| shape | PRE | index-base | stamp | CPython |
| --- | --- | --- | --- | --- |
| `from m import f as g, g as f` (one stmt) | 5018 | **5005** | 5018 | 18005 |
| `from m import f as g` / `g as f` (two stmts) | 5018 | 18018 | 18018 | 18005 |
| this ticket's package shape | ERR | PASS | PASS | PASS |

Row 1 is the regression the index-base version would have introduced, invisible
from this ticket's own test. The stamp restores PRE there.

Row 2 still differs from PRE (5018 → 18018): one of the two names becomes
correct and the other stays wrong. That is not this fix — it is a separate
pre-existing defect, measured identical on PRE and filed as
`bug-n-a-from-import-alias-resolves-its-source-through-flat-scope`.

### Gate

`make compiler/pascal26` — self-host fixedpoint verified, `69e9fbed8b22`.
`tools/gate.sh quick` GREEN. The test passes and its output matches `.expected`
exactly. The whole nilpy import-test family was run individually against both
PRE and the fix: identical on every one except this ticket's, which goes
ERR → PASS; the five with no `.expected` were compared by runtime output rather
than skipped, and are byte-identical.
- 2026-08-29 — resolved, commit PENDING-COMMIT.

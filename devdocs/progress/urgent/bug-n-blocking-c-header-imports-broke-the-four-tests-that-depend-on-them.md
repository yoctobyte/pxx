---
track: N
prio: 75
type: bug
summary: "`fix(N): a Python import can no longer resolve to a C header` (3f5511820) took out `import sqlite3` and `import stdlib` too, so four tests that exist to assert C-header imports WORK now fail to compile. The fix cannot tell an accidental resolution (`import stdio`) from the intended binding path (`import sqlite3`) — it blocked both."
---

# Blocking C-header imports also blocked the four tests that exist to prove they work

- **Type:** bug (regression, master is red) — **Track N** (Nil-Python frontend).
  Found and diagnosed by Track T; **T owns the tool, never the bug.**
- **Found:** 2026-08-13T12:40:55Z by twatch on plexus, native + full tiers.
  Consolidates three auto-filed stubs — one cause, four jobs.
- **Caused by:** `3f5511820 fix(N): a Python import can no longer resolve to a
  C header`, the only semantic commit in the watcher's 5-commit range.

## Reproduce (compiler at HEAD)

```
$ ./compiler/pascal26 test/test_nilpy_c_define_const.npy /tmp/x
pascal26:5: error: import: no unit named sqlite3 and no shim mimic_sqlite3
```

All four jobs, same shape:

| test | import that now fails |
|---|---|
| `test/test_nilpy_c_define_const.npy` | `sqlite3` |
| `test/test_nilpy_c_pointer.npy` | `stdlib` |
| `test/test_nilpy_sqlite_crud.npy` | `sqlite3` |
| `test/test_nilpy_import_sqlite.npy` | `sqlite3` |

## The contradiction, in the tests' own words

`test_nilpy_c_define_const.npy` opens with:

> *Object-like integer `#define` macros from an imported C header reach Nil
> Python too: `import sqlite3` surfaces SQLITE_OK / SQLITE_ROW / SQLITE_DONE
> (plain `#define` integers in sqlite3.h) as named constants, so a binding no
> longer has to hardcode magic numbers like 100.*

That is a test whose entire purpose is to assert the behaviour 3f5511820
removes. So this is not a subtle breakage — the fix and these four tests state
opposite intentions about the same feature, and one of them has to be wrong.

## What the fix was actually aimed at

Its companion, `bf212d975 docs(N): a Python import resolves against C headers —
import stdio compiles`, records the motivating problem: `import stdio` silently
compiling, i.e. a *Python* import accidentally resolving against whatever C
header happened to share the name. That is a real defect and worth fixing.

But `import sqlite3` reaching sqlite3.h is the **deliberate binding path** — the
mechanism the SQLite tests are built on. The fix does not distinguish the
accident from the intent; it removed the resolution entirely.

## The fork (Track N's call — this is a design decision, not a repair)

1. **The binding path stays, the accident goes.** Needs a rule that separates
   them — an explicit allow-list, an `import c.sqlite3` / `from cheader import`
   spelling, or a marker in the header set that says "this one is a binding
   target". The four tests then keep passing unchanged.
2. **The binding path is genuinely withdrawn.** Then all four tests are
   obsolete and must be updated or deleted in the same commit that withdraws
   it — and `devdocs/dev/nilpy-semantics-divergences.md` should record that
   NilPy does not bind C headers by import, since that is a real capability
   loss.

Option 1 looks right from outside the lane (the SQLite CRUD test is a
substantial, working demonstration, and NilPy's C-binding story is one of its
distinguishing features) — but it is Track N's call, and if it needs a decision
rather than a fix, that is a Track U `decide-` ticket.

**Either way master stays red until one of them lands**, which is why this is
p75 rather than the stubs' 70: it is not four separate regressions to triage,
it is one commit and one decision.

## Note for whoever verifies this

Both directions of this were briefly mis-read during triage from a **stale
compiler binary** — the tests appear to pass if `compiler/pascal26` predates
3f5511820, which is exactly the trap CLAUDE.md's "hunt async, verify against a
known sha" is about. Run `make compiler/pascal26` before believing either
result.

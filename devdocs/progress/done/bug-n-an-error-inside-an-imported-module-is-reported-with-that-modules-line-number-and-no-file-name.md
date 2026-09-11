---
slug: bug-n-an-error-inside-an-imported-module-is-reported-with-that-modules-line-number-and-no-file-name
track: N
prio: 55
type: bug
status: done
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, diagnostics, imports, misroutes]
blocked-by: []
summary: "A compile error raised inside an IMPORTED module is printed as `pascal26:<n>:` where <n> is that module's line number and nothing names the file, so the reader supplies the filename of the file they invoked. Minimal repro: a 4-line `__init__.py` doing `from . import inner`, and a bad name on `inner.py:7`, reports `pascal26:7: error: undefined variable (nosuchname)` -- a line that does not exist in the file being compiled. This is not a cosmetic diagnostic gap: it MANUFACTURES false shared-cause findings in a census. bug-n-staticmethod-is-not-a-value was filed at prio 80 saying staticmethod blocks BOTH `platform/__init__.py:31` and `platform/_pxx.py:31`; it blocks exactly ONE, and the identical line number in both rows was the tell -- both were `_pxx.py:31`. The same defect then sent the next reader chasing a DOCSTRING, because `platform/__init__.py`'s post-fix wall reads `pascal26:8: no unit named ctypes` and line 8 of that file is ``ctypes`` in prose, while the real import is `_ctypes_backend.py:8`."
---

# The repro

```
pkg/__init__.py   (4 lines)      pkg/inner.py   (7 lines)
  # line 1                         # a
  # line 2                         ...
  from . import inner              # f
  print(inner.VALUE)               VALUE = nosuchname
```

```
$ pascal26 __init__.py out
pascal26:7: error: undefined variable (nosuchname)
  near: VALUE = nosuchname >>>
```

Line 7 of a 4-line file. The `near:` context is correct and is the only thing
that gives it away — and a census reads the line, not the context.

# Why it is 55 and not a deferred diagnostic

CLAUDE.md defers a *differing* diagnostic. This one is not different, it is
**wrong about which file it is talking about**, and the failure mode is the
expensive one: it does not stop a reader, it sends them somewhere.

Two dated instances in one afternoon, both in the same census:

1. **A false shared cause.** `bug-n-staticmethod-is-not-a-value` (p80) records
   `platform/__init__.py:31` and `platform/_pxx.py:31` as two modules blocked by
   `staticmethod`. `__init__.py` contains no `staticmethod` at all — its own
   line 31 is a blank between constants. Both rows were `_pxx.py:31`, and the
   ticket's "blocks BOTH modules of the portability seam" claim, which is what
   argued it to prio 80, is an artefact of this defect. The fix cleared one
   module.
2. **A chase.** After that fix, `platform/__init__.py` reports
   `pascal26:8: import: no unit named ctypes`, and line 8 of `__init__.py` is
   the RST prose ```` ``ctypes`` ````. Ten minutes went into testing whether a
   docstring was being read as an import. It was not: the line belongs to
   `_ctypes_backend.py`, whose line 8 is `import ctypes`.

**The identical line number appearing in two modules is the diagnostic tell**,
and it reads exactly like a shared cause — which is the thing a census is for.

# What the fix looks like

The reported position needs the module's NAME beside the line, at least for a
position that did not come from the file on the command line. `near:` already
proves the compiler knows the right source text; only the label is missing.


## CLOSED BY EVENTS — verified 2026-09-11 (frankB), compiler `06f130b576f5`

Fixed at **`584ca8ea8`** (owner, 09-11 04:58, `fix(N): an error inside an
imported NilPy module names the module`). `PyLexAppend` marked the appended
module's token range with an EMPTY path — it ended the open Pascal range and
started no correct one. It now passes the real path, so `PasSrcOfTok` answers
and `Error`'s `in:` line names the module.

Verified against this ticket's own repro and against the corpus instance:

| case | before (pinned `095ef4811a5b`) | now |
| --- | --- | --- |
| one level: `m.npy` imports `inner.py`, bad name at `inner.py:7` | `pascal26:7:` and no file | `in: .../inner.py` |
| nested: `from . import inner` inside `pkg/__init__.py` | `pascal26:7:` and no file | `in: .../pkg/inner.py` |
| corpus: `bindings.py` | `pascal26:95:` and no file | `in: .../platform/__init__.py` |

The corpus row is the one that matters: the line number is still 95 and 95 is
still not a line of `bindings.py`, but the file is now named, so the reader is
no longer supplying the wrong one.

### How this ticket nearly got FIXED TWICE, which is the reusable part

I re-measured it tonight as still broken and started on a fix. The measurement
was made with a binary built from PRE-PULL sources: `584ca8ea8` arrived in the
`tools/sync.sh` pull at my own previous commit, and I ran the repro without
rebuilding. **`b00c6751b693` (pre-pull) prints no `in:`; `06f130b576f5` (same
HEAD, post-pull) prints it.** Same tree identity, two binaries, opposite
answers — and the stale one is the one that agrees with the ticket, which is
what makes it convincing.

This is CLAUDE.md's own sequence — PUSH, LET THE PULL SETTLE, **REBUILD**,
MEASURE — with the rebuild dropped, and the failure mode is the one that rule
does not spell out: a stale binary does not only make you claim a green you did
not earn, **it makes an already-fixed ticket reproduce.** A ticket that
reproduces is the strongest possible argument for working on it, so the stale
reading does not merely mislead, it recruits.

The discriminator that settled it cost one command and is the one to reach for:
run the repro under the **pinned** compiler as well. Two binaries that disagree
about a defect date it; a single binary can only confirm the ticket.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6eac77f8f.

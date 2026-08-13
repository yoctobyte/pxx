---
track: T
prio: 45
type: bug
summary: "pydiff.py reports a bogus DIFF for any file given as a relative path: run_cpython passes the full relative path while setting cwd to that path's dirname, so CPython exits 2 and every line reads 'cpython: <no line>'"
status: done
---

# pydiff's CPython arm fails on a relative path, and it looks like a real DIFF

`tools/pydiff.py run test/test_nilpy_foo.npy` reports a full-file divergence:

```
DIFF test/test_nilpy_overridden_class_attribute.npy
  exit: cpython=2 pxx=0
  line 1:
    cpython: <no line>
    pxx    : in ctor: derived
  ...
```

The same file by absolute path is `ok (11 lines of stdout agree)`.

## Cause

`run_cpython` (tools/pydiff.py:57) runs `[sys.executable, path]` with
`cwd=os.path.dirname(path)`. With a relative `test/x.npy` that is
`python3 test/x.npy` **from inside `test/`** — file not found, CPython exit 2,
empty stdout. `run_pxx` directly below it gets this right: it passes
`os.path.basename(path)` with the same cwd.

One-line fix: `os.path.basename(path)` in `run_cpython` too (or make `path`
absolute once at entry, which also covers the `bisect`/`probe` subcommands at
:147, :440, :470).

## Why it matters more than a usage wart

pydiff is the CPython oracle — the tool the debugging playbook says to reach for
*instead* of reasoning. Its failure mode here is not an error message but a
**plausible-looking DIFF where every pxx line is present and every CPython line
is missing**, on the exact invocation form (`tools/pydiff.py run test/...`) an
agent working from the repo root naturally types. Read quickly it says "pxx
prints, CPython prints nothing", which invites a hunt for a divergence that does
not exist. `exit: cpython=2` is the only tell.

Found 2026-08-07 while gating
[[bug-nilpy-overridden-class-attribute-read-through-an-instance-gives-the-base-value]];
cost one wrong-turn probe before the exit code was noticed.

## Gate

`tools/testmgr.py --tier full` per Track T's rule, plus: the same file diffed
by relative and absolute path must give the same verdict.

## Log
- 2026-08-13 — resolved, commit e0313bbc4.

## Resolution — 2026-08-13 (Track T)

`run_cpython` now runs `os.path.basename(path)` with `cwd` set to the file's
directory — the same shape `run_pxx` directly below it already used. Both arms
therefore execute from the file's own directory, so relative imports and sibling
data files resolve identically for the oracle and for pxx, which is the property
the `cwd` was there for in the first place.

Fixed at the single choke point rather than at the three call sites the ticket
lists (`run` :471, `bisect` :147, `probe` :440): all three reach CPython through
this one function, and a rule enforced in one place cannot drift between them.

Gate, exactly as the ticket asks — the same file by both path forms:

```
$ tools/pydiff.py run test/quick_canary_nilpy.npy
ok test/quick_canary_nilpy.npy (24 lines of stdout agree)
$ tools/pydiff.py run /home/neo/pxx/test/quick_canary_nilpy.npy
ok /home/neo/pxx/test/quick_canary_nilpy.npy (24 lines of stdout agree)
```

Before the fix the first form reported a whole-file DIFF with `exit: cpython=2`.

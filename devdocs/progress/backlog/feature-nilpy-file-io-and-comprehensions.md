---
track: N
prio: 55
type: feature
---

# NilPy: file I/O (`with open`), list comprehensions, and dict literals-in-args

Hangs off [[feature-nilpy-corpus-uforth]]. uforth's wall as of 2026-07-20 is
line 1228, and it is a CLUSTER, not a single feature — three things land on
consecutive lines:

```python
with open(abs_path, "r", encoding="utf-8") as f:
    lines = [raw.rstrip("\n") for raw in f]          # comprehension + file iter
source_id = self._alloc_fileid(
    {"kind": "source", "path": abs_path, "lines": lines}   # dict literal as arg
)
```

## The pieces, roughly in dependency order

1. **`with` statement** — a context manager. For `open`, the only censused use,
   this desugars to: open, run the body, close on every exit path (including
   exceptions). One site, so a narrow `with open(...) as f:` form is enough;
   the general protocol (`__enter__`/`__exit__`) is not needed yet.
2. **A file object** — `open(path, mode, encoding=...)`, iterable BY LINE
   (`for raw in f`), plus `.read()`. This is the real work: a PAL/RTL file
   primitive plus an iterator that yields lines. `sys.stdin` (filed separately)
   needs the same object, so build it once.
3. **List comprehensions** — `[expr for x in it]`, and with a filter
   (`[expr for x in it if cond]`). 4 sites. Desugars to a fresh TPyList built
   by a loop; the loop machinery already exists (PyParseForIn), so this is
   mostly a new expression form that emits an accumulate.
4. **A dict/set literal as a call ARGUMENT** — `f({...})`. Literals work in
   assignment position; this needs them accepted in an argument position too.
   Likely small.

## Smaller items still past this (census in uforth.py)

- **lambda** (4) — `default_factory=lambda: ...` already handled for the one
  dataclass case; general lambda still open.
- **del** (4), **nonlocal** (1).
- **f-string format specs** `{x:05x}` (3) — pyformat_of exists; verify these.
- **`sys.stdin` + `select.select`** — the hardest: needs the file object from
  (2) plus a select primitive. 8 stdin sites.

## Gate

Each piece lands green independently with a CPython-diffed `.npy` case +
`--tier quick` + self-host byte-identical + `make fpc-check` clean. The file
object in particular needs a test that reads a real temp file and matches
CPython line for line.

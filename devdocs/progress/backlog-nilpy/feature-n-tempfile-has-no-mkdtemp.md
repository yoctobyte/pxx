---
track: B
prio: 70
type: feature
blocked-by: []
summary: "`tempfile.mkdtemp(prefix=...)` is absent from lib/rtl/tempfile.pas, which carries only gettempdir and a NamedTemporaryFile class. It is the lekkerzeilen closure's wall as of 2026-09-12 (__main__.py:115, `root = tempfile.mkdtemp(prefix=\"lz-conform-\")`) and the FIRST wall in that closure that is a LIBRARY gap rather than a parser gap — every one of the six cleared before it was a parser gap, so this is a change in the character of what is left. Diagnosed with the unnamed-line trap in play: the error prints as a bare `pascal26:115:` with NO file name, which reads as app.py:115 to anyone who supplies the file they invoked; grep found the single mkdtemp in the tree and it is __main__.py. A correct mkdtemp must CREATE the directory and must not hand back a name it did not create — returning a plausible unique-looking path without an exclusive create is a silent wrong value under concurrency, which is the one outcome worth refusing over."
---

# tempfile has no mkdtemp

`lib/rtl/tempfile.pas` exports `gettempdir`, `TfSysTempDir` and a
`NamedTemporaryFile` class. `mkdtemp` is not there.

## Where it bites

`lekkerzeilen/__main__.py:115`:

```python
root = tempfile.mkdtemp(prefix="lz-conform-")
```

```
pascal26:115: error: no member mkdtemp came of the qualifier tempfile
```

## What it must do

CPython's contract: create a directory nobody else can have, return its absolute
path, and leave removal to the caller. Two things a shim must not get wrong:

- **Create, exclusively.** `mkdir` failing with EEXIST is the retry signal. A shim
  that builds a random-looking name and returns it WITHOUT creating the directory
  passes a smoke test and races in production — a plausible wrong value with no
  diagnostic.
- **Mode 0700.** CPython creates the directory private to the user. A shim that
  leaves it 0777 is a quieter bug than a missing function.

`prefix`, `suffix` and `dir` are the keyword arguments real code passes; `dir`
defaults to `gettempdir()`, which this unit already has.

## Scope note

Filed on track B (lib/rtl) rather than N: there is no compiler or parser gap here,
and `tempfile` already resolves — only the member is missing.

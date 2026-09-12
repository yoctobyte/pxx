---
track: B
prio: 70
type: feature
blocked-by: []
summary: "`tempfile.mkdtemp(prefix=...)` is absent from lib/rtl/tempfile.pas, which carries only gettempdir and a NamedTemporaryFile class. It is the lekkerzeilen closure's wall as of 2026-09-12 (__main__.py:115, `root = tempfile.mkdtemp(prefix=\"lz-conform-\")`) and the FIRST wall in that closure that is a LIBRARY gap rather than a parser gap — every one of the six cleared before it was a parser gap, so this is a change in the character of what is left. Diagnosed with the unnamed-line trap in play: the error prints as a bare `pascal26:115:` with NO file name, which reads as app.py:115 to anyone who supplies the file they invoked; grep found the single mkdtemp in the tree and it is __main__.py. A correct mkdtemp must CREATE the directory and must not hand back a name it did not create — returning a plausible unique-looking path without an exclusive create is a silent wrong value under concurrency, which is the one outcome worth refusing over."
status: done
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

## Log
- 2026-09-12 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## How it was fixed (2026-09-12)

`lib/rtl/tempfile.pas` gained `mkdtemp(suffix, prefix, dir)` — the three
keyword arguments real code passes, `dir` defaulting to `gettempdir()`.

It **creates** the directory and only returns a name it created: the loop calls
`PalMkdir` and retries on failure (64 attempts), so it can never hand back a
plausible unique-looking path it does not own. That was the one outcome the
summary said was worth refusing over, and it is why this is a create-loop and
not a name generator.

`PalMkdir` directly, **not `CreateDir`**, and the reason was measured rather
than assumed: `CreateDir` passes 0o777, and with the umask here (002) that
leaves **0o775** — group-writable as well as world-readable. The ticket body
above guessed 0o755 at that spot and was wrong; CPython's `mkdtemp` promises
0o700 and this passes `TF_MKDTEMP_MODE = 448` to get it.

Exhaustion raises rather than returning `''`, carrying the last `mkdir` rc.

## The guard, and what makes the MODE row real

`test/test_nilpy_tempfile_mkdtemp.npy` — 11 rows, Makefile target
`test_nilpy_mkdtemp`. The load-bearing one is `MODE 0o700`: a default-umask
`CreateDir` implementation passes every other row in the file and fails only
that one.

**The pin is NOT a positive control for this change and was briefly used as
one.** `lib/rtl` is read LIVE, so the pinned compiler compiles the new fixture
happily — it is not an older library, it is the same library. The control that
does work is a deliberate break: setting the mode to 511 makes the MODE row
print `0o775` and go red, which is what proves the row can fail at all.

The fixture also removes its own directories, using the `os.rmdir` added the
same evening ([[bug-n-os-has-no-rmdir]]) — measured at **delta 0 inodes over
three runs**, which matters more on seven, where `/tmp` is a tmpfs and the
binding resource is inodes rather than bytes.

## Closure effect

It was the wall at `__main__.py:115`. With it and the `os.rmdir` beside it the
lekkerzeilen closure moved **115 -> 138**, and after
`zlib.ZLIB_VERSION` cleared 141 it now reaches `__main__.py:312`
(`__doc__`) with **all of app.py passing** — 4344 lines of warnings and no
error.

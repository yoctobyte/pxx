---
track: D
prio: 25
type: docs
blocked-by: []
summary: "`-Fu<dir>` is how NilPy finds a third-party Python package, and it is absent from the compiler's usage line. Its absence misdiagnoses as `import: no unit named X` — a 'feature missing' message for a feature that exists. Cost a wrong first diagnosis on the first corpus attempt; will bite the next person wiring one."
---

# `-Fu` is how a Python package is found, and nothing says so

- **Type:** docs / discoverability — **Track D** (usage line lives in
  `compiler/**`, so the one-line code change is Track A; the prose is D).
- **Found:** 2026-08-17, first attempt at a third-party Python corpus
  ([[feature-nilpy-thirdparty-libraries-as-targets]]).

## The problem

To compile NilPy code that imports a third-party package:

```sh
./compiler/pascal26 -Fu/abs/path/to/library_candidates/webencodings drv.npy drv
```

That works — it resolves `from webencodings import lookup, decode, encode` and
begins compiling the package's `__init__.py`. **But `-Fu` is not in the
compiler's usage line**, which prints only:

```
usage: pascal26/PXX [--debug] [--dump-ir] [-dNAME] [-uNAME] [-Mobjfpc]
       [--strict-overload] [--strict-operator] [--strict-case]
       [--strict-python] [--no-unhandled-handler] <src> [out]
```

## Why it matters more than a missing flag usually would

Without it the failure is:

```
error: import: no unit named webencodings and no shim mimic_webencodings
```

which reads as **"this feature does not exist"** for a feature that does. My
first diagnosis was "pxx cannot resolve third-party packages at all", and the
natural next move — the one CPython teaches — is `sys.path.insert(0, ...)`,
which silently does nothing because `sys.path` is a RUNTIME mechanism and pxx
resolves imports at COMPILE time. Neither the message nor the usage line points
anywhere.

This is the same shape as a recent day lost on synapse: the mechanism existed
and nothing pointed at it.

## What to do

1. **Add `-Fu<dir>` to the usage line** (one line, Track A).
2. **Improve the message.** `no unit named X` should mention the search path —
   e.g. `...and no directory on the unit search path contains it (-Fu<dir>)`.
   That single clause converts a dead end into a next step.
3. **Document it** in the NilPy docs where third-party imports are discussed:
   `-Fu` takes the directory *containing* the package directory (for
   `library_candidates/webencodings/webencodings/`, pass
   `library_candidates/webencodings`), matching Python's own "parent of the
   package" path convention.

## Note

`sys.path` manipulation is not a bug and should not be made to work — a compile
-time resolver cannot honour a runtime list. Worth saying explicitly in the docs
so the next person does not file it: the NilPy answer to `sys.path` is `-Fu`.

> **2026-08-17 — the wall table quoted above is SUPERSEDED.** It came from a scan
> that passed only the scanned file's own `-Fu` root, so cross-package imports
> (`tinycss2` -> `webencodings`) recorded as compiler walls. Corrected table and
> the tool that now produces it (`tools/nilpy_ladder.py`):
> [[bug-t-the-ladder-scan-passes-only-one-root-so-cross-package-imports-read-as-walls]].
> The `webencodings` and `constants` rows were artefacts and are gone; the real
> top two are `undefined variable (digits)` (8 files) and
> `undefined variable (CodecInfo)` (7 files).

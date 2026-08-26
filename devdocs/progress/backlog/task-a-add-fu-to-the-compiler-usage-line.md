---
track: A
prio: 40
type: task
blocked-by: []
summary: "One line: `-FuDIR` is missing from the compiler's own `usage:` output, so the flag that makes a third-party Python package resolvable is undiscoverable from the compiler itself. The docs half is done (doc-n-fu-is-how-a-python-package-is-found); this is the code half that ticket split off."
---

# Add `-Fu` (and `-I`) to the compiler's usage line

- **Type:** task — **Track A** (the usage string lives in `compiler/**`).
- Split from [[doc-n-fu-is-how-a-python-package-is-found]], resolved 2026-08-19:
  the prose is Track D's and is written; the usage line is not Track D's to
  edit, and leaving the remainder inside a resolved docs ticket would lose it.

## What is missing

The compiler prints:

```
usage: pascal26/PXX [--debug] [--dump-ir] [-dNAME] [-uNAME] [-Mobjfpc]
       [--strict-overload] [--strict-operator] [--strict-case]
       [--strict-python] [--no-unhandled-handler] <src> [out]
```

`-FuDIR` is absent, and it is the flag that turns

```
error: import: no unit named mypkg and no shim mimic_mypkg
```

from "this feature does not exist" into "you did not say where to look". `-I`
is absent for the same reason and belongs in the same line.

## Note, measured 2026-08-19 against pin v364

`-Fu` takes the directory that **contains** the package, not the package
directory: with `pkgdir/mypkg/__init__.py`, `from mypkg import greet` resolves
under `-Fu…/pkgdir` and fails under `-Fu…/pkgdir/mypkg`. If the usage line
gains a one-word gloss, that is the thing worth saying.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick`. No behaviour change.

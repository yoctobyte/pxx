---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`os.rmdir(d)` answers `undefined variable (os)` — the member is absent, not the module: `os.path.isdir`, `os.listdir` and `os.sep` all resolve in the same program. So does `os.getpid()`. Distinguish this from `os.remove` and `os.makedirs`, which DO exist as compiler-provided calls and only fail when named as a bare VALUE (`print(os.remove)` -> `os.remove is a compiler-provided ...`) — that is a different, already-known shape and not this. FIXED 2026-09-12, same day it was found: `PyPalRmdir` in compiler/builtin/pypal.pas (reusing NR_UNLINKAT with AT_REMOVEDIR = 512, since Linux has no at-family rmdir, so no number was added to the six per-target tables), `pyos_rmdir` in compiler/builtin/pylib.pas, and the `os.rmdir` -> `pyos_rmdir` row in the dotted table in compiler/pyparser.inc. Deliberately NON-recursive, matching CPython. Because it is a BUILTIN addition it is available to the live compiler immediately and INERT for every $(PXX_STABLE) consumer until the owner pins. It retired the clause this summary used to carry: test/test_nilpy_tempfile_mkdtemp.npy no longer leaks — it removes its own directories and was measured at delta 0 inodes over three runs. Two residuals stay: `shutil.rmtree` is still absent (`no member rmtree came of the qualifier shutil`) so `tempfile.TemporaryDirectory` still cannot be written, which is track B; and `os.getpid()` is still missing, split out as [[bug-n-os-has-no-getpid]] because it needs six per-target syscall numbers where rmdir needed none. Low prio because the consequence is leaked empty directories a tmp reaper collects, not a wrong answer; it is worth fixing because it is what every cleanup and TemporaryDirectory pattern needs, and because `tempfile.TemporaryDirectory` cannot be written without it."
status: done
---

# os has no rmdir

```python
import os
os.rmdir(d)        # error: undefined variable (os)
os.path.isdir(d)   # fine
os.listdir("/tmp") # fine
os.sep             # fine
os.getpid()        # error: undefined variable (os)
```

## The diagnostic is misleading and that is the expensive part

`undefined variable (os)` names the MODULE when the module is bound and working
three lines earlier. Anyone reading it looks at the import first. The message for
a genuinely missing member of a bound qualifier should look like the one
`tempfile` gives — `no member mkdtemp came of the qualifier tempfile` — which is
precise and sends the reader to the right place. `shutil.rmtree` produces exactly
that better form, so the two diagnostics disagree about the same class of gap.

## Not the same as os.remove / os.makedirs

Those exist as compiler-provided calls and refuse only as bare values:

```
print(os.remove)     -> Nil Python: os.remove is a compiler-provided ...
print(os.makedirs)   -> Nil Python: os.makedirs is a compiler-provided ...
```

Do not "fix" this ticket by finding those and concluding the family works.

## Why it matters beyond tidiness

`tempfile.TemporaryDirectory` is the natural companion to the `mkdtemp` landed on
2026-09-12 and cannot be written without a directory removal. Any NilPy program
that makes a scratch directory currently has no way to clean it up.

## Log
- 2026-09-12 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d0d490ad2.

## How it was fixed (2026-09-12)

Three places, and the cheapness is the point:

- `compiler/builtin/pypal.pas` — `PyPalRmdir`, reusing **`NR_UNLINKAT` with
  `PYPAL_AT_REMOVEDIR = 512`**. Linux has no at-family `rmdir`, so
  `unlinkat(AT_FDCWD, path, AT_REMOVEDIR)` *is* the syscall, and no number had
  to be added to the six per-target `NR_*` tables. That is the whole reason
  this was same-day work and `os.getpid()` was not.
- `compiler/builtin/pylib.pas` — `pyos_rmdir`, raising through
  `pyos_raise_ioerror` on a negative return so a non-empty directory or a
  missing path surfaces as an exception rather than a quiet rc.
- `compiler/pyparser.inc` — one row in the dotted stdlib table,
  `os.rmdir -> pyos_rmdir`.

**Deliberately non-recursive**, matching CPython: `rmdir` on a non-empty
directory raises. The fixture asserts both halves (`NONEMPTY raised True`,
`MISSING raised`).

## It is a BUILTIN addition, so it is inert until a pin

`compiler/builtin/*.pas` is resolved CWD-relative by the live compiler, so this
works immediately in the dev loop and is **invisible to every
`$(PXX_STABLE)` consumer until the owner pins**. `make pin` is owner-only; this
is recorded here rather than waited on.

## Residuals, each with an owner

- `os.getpid()` — still absent, same misleading diagnostic. Split out as
  [[bug-n-os-has-no-getpid]] (track N, p30) because it needs six correct
  per-target syscall numbers where this needed none.
- `shutil.rmtree` — still absent (`no member rmtree came of the qualifier
  shutil`), so `tempfile.TemporaryDirectory` still cannot be written. That is
  **track B / lib/rtl**, not this ticket.

## What it retired

This ticket's own summary used to say the mkdtemp fixture "has to leave two
empty directories behind every run and says so". It does not any more — it
cleans up with this `rmdir` and measures delta 0 inodes over three runs. The
summary was corrected in the same commit, not left for a later reader.

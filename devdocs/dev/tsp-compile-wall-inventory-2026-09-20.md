# What is still missing to compile TSP — inventory, 2026-09-20 (frankH)

Asked for by the owner, relayed by frankuser: *"let's inventarise what's still
missing to compile TSP. i sortof assume those would be minor defects"*. This is
the answer to that question and nothing more — **a list, not a plan, and no
fixes were made for it.**

Method: attempt the target and let the failures name the walls, in the order
they actually block. Per-file census population `tsp/**/*.py` = **67 files**,
run from a clean `git archive` of TSP, oracle = compile success. Last row:
**47 of 67 compile at pxx `45b8571d7`.** TSP tree for the file-level readings
below: live working tree `a143976` (it carries the owner's uncommitted edits).

**Do not quote 67 without checking it.** `find . -name '*.py'` over the whole
TSP archive answers **91**; `tsp/**/*.py` answers 67. The two are different
populations and only the second is this census's.

## The headline: one of these is not a minor defect, and it is not ours

**Half the remaining board is the ctypes seam, and it is blocked on APPLICATION
code that does not exist yet — not on the compiler.**

`tsp/platform/__init__.py` gates on `try: import __pxx__`. The `except` arm
takes `_ctypes_backend` (today's path; walls at `ctypes.c_uint`). The `else`
arm — the one the marker module would switch on — is
`from . import _pxx_backend as _backend` at line 107, and **`_pxx_backend.py`
is not in that directory** (measured 2026-09-20: `__init__.py`,
`_ctypes_backend.py`, `_gl.py`, `_sdl2.py`, `_vocab.py`). So implementing
`__pxx__` moves the wall one line earlier and **buys zero units**.

What that file has to be: lekkerzeilen solved the identical seam in
`platform/_pxx.py`, opening with `import "/usr/include/SDL2/SDL.h"` and
`import "/usr/include/GL/gl.h"` — pxx's own C-header import standing in for
ctypes. TSP's tree contains no C-header import anywhere. TSP's own docstring
says the same thing in its own words: *"Copy and adapt it from there when TSP
starts targeting PXX."*

**HOW BIG THAT PORT IS — CORRECTED 2026-09-20, AND THE FIRST ANSWER WAS A FILE
SIZE WEARING A COST'S CLOTHES.** This note first cited `_pxx.py`'s **974 lines**
as the estimate. 974 is a true measurement of that FILE and it was never
measured as a port cost; frankz-e5 retracted it having passed it on, and the
number had reached this note the same way. **It is not the estimate and nothing
should be sized on it.**

What is measured, by me, at 2026-09-20, with the method beside it: the two
platform layers are the **same design file-for-file, one file apart** —

    lekkerzeilen/platform/   __init__.py  _ctypes_backend.py  _gl.py  _pxx.py  _sdl2.py  _vocab.py
    tsp/platform/            __init__.py  _ctypes_backend.py  _gl.py           _sdl2.py  _vocab.py

and the corresponding files differ by `diff | grep -c '^[<>]'` of **30
(`_gl.py`), 67 (`_sdl2.py`), 41 (`_vocab.py`), 217 (`__init__.py`)**. So the
missing file is **copy-and-adapt against a near-identical surface**, tens to low
hundreds of changed lines, not a thousand lines of new work.

**A second set — 27 / 56 / 40 / 202 — was carried here for an hour and is now
RETIRED, by mechanism rather than by preference.** It came from
`diff -u | grep -c '^[+-][^+-]'`, written to skip the `---`/`+++` headers. The
class `[^+-]` **requires a character after the sign**, and a changed BLANK line
is a bare `+` or `-`, so every added or removed blank line is silently dropped.
Run on this tree, the two commands and the blanks account for each other
exactly:

    file           plain   with [^+-]   blank-only   sum
    _gl.py           30        27            3        30
    _sdl2.py         67        56           11        67
    _vocab.py        41        40            1        41
    __init__.py     217       202           15       217

**This is a refutation and not a disagreement, which is why one row replaces
two.** The tree's rule is to carry both numbers when a re-run disagrees — that
is for when you cannot say WHY. Here the second command has a failure mode, the
failure mode was exercised on two independent checkouts neither author's
measurement came from, and it did not fail. Tree excluded, method identified,
no residual. Found by frankuser, verified by frankz-e5 and again here.

**AND THE PORT IS NOT HAPPENING IN THIS WINDOW** — the owner's decision,
relayed 2026-09-20: *"for now i rather keep it as is. both lekkerzeilen and TSP
run fine under CPython and Linux. we are good and should not overcomplicate."*
Each demo keeps its own platform layer and pxx does not absorb `_pxx.py` as a
general loader. Row 3 is therefore off the board as work, and stays here as the
answer to what is missing.

## Ordered walls

| # | wall | shape | known/new | whose |
| --- | --- | --- | --- | --- |
| 1 | `import threading` | refuses without `--threadsafe`, and says so | known | **CONFIGURATION — not a wall, not a defect** |
| 2 | ~~`import wave`~~ | **CLEARED 2026-09-20** — `lib/rtl/mimic_wave.pas`; `voice.py` now walls on `threading.Condition:79` instead | done | was Track N |
| 3 | ctypes seam | `_pxx_backend.py` does not exist; see headline | new | **application** |
| 3b | `__pxx__` marker | not built — 0 occurrences in `compiler/` and `lib/`, 7 prose files in `devdocs/`, at HEAD | known (p80) | compiler, but see headline |
| 4 | `dataclasses.replace` | `shape.py:115`, `:135`; receiver is a dict value in a comprehension | known ticket (p45) | compiler |
| 5 | `@dataclass(frozen=True)` | `director.py:37`; the refusal is correct, the work is a store guard | known ticket (p40) | compiler |
| 6 | `subprocess.run(cwd=)` | `menu.py:141`, `:161` | known | compiler |
| 7 | `random.Random(seed)` | `smoke.py:60` **only** — `commentary.py` is behind `voice.py`'s threading wall. **NOT a missing feature: it silently evaluated to a float**; fixed 2026-09-21, class still absent | see note | compiler |
| 8 | keyword through a callable value | `tsp/historic.py:531`; needs `pyvar_callv_kw`, >4 positional | known | compiler |

Module surface: **26** distinct third-party/stdlib modules imported; **23
resolve.** The three that do not are `ctypes`, `__pxx__` and `wave`.

**Row 1 is a flag, not a wall.** `--threadsafe` exists, the diagnostic names it,
and nothing is missing. It is in the table because it appears in the census's
first-error column three times and would otherwise read as three defects. Nobody
should spend a morning on it.

**Row 2 was independent of row 3, and is now done.** `wave` was ours, small, a
plain stdlib module, and — unlike the ctypes imports — `tsp/voice.py:29` imports
it **unguarded**, so no marker module and no application edit could route around
it. Built the same day as this note: `lib/rtl/mimic_wave.pas`, with a 63-row
differential green under CPython, under pxx at HEAD and under the pin, writing
files byte-identical to CPython's own `wave`.

**It did NOT deliver a compiling unit, and that is the caveat below working as
intended.** With `--threadsafe`, `voice.py`'s wall moves from `wave` to
`threading.Condition` at line 79 — a different hole in a different lane. The
wall is cleared; the unit is not. **And `wave` was never a first-error row at
all**: `voice.py`'s first error was always `threading` at line 26, three lines
above the `wave` import. The census could not have named it. It came from the
module-surface scan (26 imported, 23 resolve), which is the one instrument here
that sees past a file's first failure.

## On "i sortof assume those would be minor defects"

Right for rows 2 and 4–8: ordinary Python, ordinary gaps, each a contained
compiler change. Row 1 is not a defect at all.

**Row 3 is the refutation.** It is not minor and it is not a defect — it is
**unwritten application code**, and no amount of compiler work reaches it. It is
also the largest single population on the board (10 of 20 failures at the last
census: 3 direct ctypes imports plus 7 downstream of that one file).

Its SIZE is the corrected figure above — copy-and-adapt against a near-identical
surface, tens to low hundreds of changed lines per file — **not** the "roughly a
thousand lines" this paragraph said until 2026-09-20. That phrase was the
retracted 974 surviving in a second spelling after the first was fixed, which is
this tree's own sibling-spelling rule arriving in its own document: the arm that
gets fixed is the one you were looking at.

So: TSP's *compiler* gap is small and does look minor. TSP's *remaining* gap is
mostly one piece of porting, in the owner's own repo.

## RE-SWEEP 2026-09-21 — the board did not move, and that is the result

Population `find tsp -name '*.py'` = **67**, failures **20**, so **47 of 67** —
**identical to `45b8571d7`**, at pxx `8e60c44be` plus the stdlib case-fold fix,
with `--threadsafe`.

**`wave` landing delivered ZERO units.** The ticket said it would clear a wall
without delivering a unit; that was a prediction and is now a measurement.
`voice.py` moved from `wave` to `threading.Condition` and the count moved not
at all. Anyone quoting "47 of 67" should quote it as a number that has now
survived two compiler fixes.

**And three board rows are ONE site.** `commentary.py`, `__main__.py` and
`voice.py` all report `threading.Condition` at line **79** — but
`commentary.py:79` is a `def` and `__main__.py:79` is `if args.at:`. Only
`voice.py:79` is `self._cv = threading.Condition()`; the other two import it,
and an error inside an imported module prints that module's line number with no
file name, so the reader supplies the file they invoked.

    3 diagnostics  ->  1 defect  ->  at least 3 files behind it

That is a LOWER bound on yield, which is the opposite of what this instrument
normally gives. `provider.py` imports `voice` too and is also behind
`frozen=True`, so it needs both.

**Row 8 is placed**: `tsp/historic.py:531`. It had been recorded with a
mechanism and no file, because it came off a census column rather than a
reproduction.

Mechanism grouping for rows 4–8:
`devdocs/dev/tsp-rows-4-8-what-shares-a-cause.md`.

## What this inventory does NOT establish

- **The count is a direction, not a size.** The census instrument reports the
  FIRST error per file; clearing one wall routinely delivers its whole
  population to the next wall in the same file. Rows 4–8 are shapes that block
  somebody, not a measure of how much work each is worth.
- **The oracle is compile success, so this is blind to a silent wrong value** —
  the class we most care about. TSP has no expected output to diff. Quote
  "47 of 67" with that attached.
- No row here was re-measured after `45b8571d7`; the file-level readings
  (`_pxx_backend.py` absent, `voice.py:29`, the line numbers in rows 4–7) were
  taken 2026-09-20 against TSP's live tree.

frankH is READ-ONLY in `~/tuxspaceprogram`. Rows 3 and 3b are the owner's to
unpark; everything else is Track N's.

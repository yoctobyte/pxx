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
`platform/_pxx.py`, **974 lines**, opening with
`import "/usr/include/SDL2/SDL.h"` and `import "/usr/include/GL/gl.h"` — pxx's
own C-header import standing in for ctypes. TSP's tree contains no C-header
import anywhere. TSP's own docstring says the same thing in its own words:
*"Copy and adapt it from there when TSP starts targeting PXX."*

## Ordered walls

| # | wall | shape | known/new | whose |
| --- | --- | --- | --- | --- |
| 1 | `import threading` | refuses without `--threadsafe`, and says so | known | **CONFIGURATION — not a wall, not a defect** |
| 2 | `import wave` | no unit, no shim; `tsp/voice.py:29`, **unguarded** | new | compiler (Track N) |
| 3 | ctypes seam | `_pxx_backend.py` does not exist; see headline | new | **application** |
| 3b | `__pxx__` marker | not built — 0 occurrences in `compiler/` and `lib/`, 7 prose files in `devdocs/`, at HEAD | known (p80) | compiler, but see headline |
| 4 | `dataclasses.replace` | `shape.py:115`, `:135`; receiver is a dict value in a comprehension | known ticket (p45) | compiler |
| 5 | `@dataclass(frozen=True)` | `director.py:37`; the refusal is correct, the work is a store guard | known ticket (p40) | compiler |
| 6 | `subprocess.run(cwd=)` | `menu.py:141`, `:161` | known | compiler |
| 7 | `random.Random(seed)` | `commentary.py:64`, `smoke.py:60`; per-instance RNG class absent | known ticket (p40) | compiler |
| 8 | keyword through a callable value | needs `pyvar_callv_kw`, >4 positional | known | compiler |

Module surface: **26** distinct third-party/stdlib modules imported; **23
resolve.** The three that do not are `ctypes`, `__pxx__` and `wave`.

**Row 1 is a flag, not a wall.** `--threadsafe` exists, the diagnostic names it,
and nothing is missing. It is in the table because it appears in the census's
first-error column three times and would otherwise read as three defects. Nobody
should spend a morning on it.

**Row 2 is independent of row 3** and is worth doing on its own merits: `wave`
is ours, it is small, it is a plain stdlib module, and — unlike the ctypes
imports — `tsp/voice.py:29` imports it **unguarded**, so no marker module and no
application edit can route around it. It does not wait on the seam and the seam
does not wait on it.

## On "i sortof assume those would be minor defects"

Right for rows 2 and 4–8: ordinary Python, ordinary gaps, each a contained
compiler change. Row 1 is not a defect at all.

**Row 3 is the refutation.** It is not minor and it is not a defect — it is
unwritten application code, roughly a thousand lines by the only worked example
we have, and no amount of compiler work reaches it. It is also the largest
single population on the board (10 of 20 failures at the last census: 3 direct
ctypes imports plus 7 downstream of that one file).

So: TSP's *compiler* gap is small and does look minor. TSP's *remaining* gap is
mostly one piece of porting, in the owner's own repo.

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

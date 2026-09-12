---
track: N
prio: 70
type: feature
blocked-by: []
summary: "`__doc__` answers `undefined variable (__doc__)` and is the lekkerzeilen closure's wall as of 2026-09-12 — CITE THE CONSTRUCT, NOT THE LINE: `print(__doc__.strip())` in `__main__.py`'s `--help` path, which is line **312 in the owner's WORKING TREE and 299 at HEAD**, because that file is modified on disk by an in-flight backend port and the closure compiles the working tree, with ALL of app.py now compiling. The module docstring is not missing from the compiler — it is deliberately THROWN AWAY: compiler/pyparser.inc:41629 consumes a leading module string literal with the comment \"A leading module docstring may precede the imports; consume it\" and keeps nothing. So the fix is to retain it, not to parse anything new, and `sys.platform` at compiler/pyparser.inc:12934 is the emit pattern to copy verbatim (AN_STR_LIT + StoredName + ASTTk := Ord(tyString)). TWO THINGS MAKE THIS BIGGER THAN IT LOOKS, both capable of a silent wrong value: a module with NO docstring must give `None`, not `''` — the call site is `print(__doc__.strip())`, which raises on None in CPython and would quietly print a blank line if we hand back an empty string; and `__doc__` is PER-MODULE, so an imported module reading its own `__doc__` must not see the main module's. Neither shows up as a compile error."
status: done
---

# `__doc__` is consumed and discarded

```python
"""A docstring."""
print(__doc__.strip())    # error: undefined variable (__doc__)
```

`lekkerzeilen/__main__.py:312`, in the `--help` path:

```python
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
```

## The line number names no file, and that is the documented trap

The diagnostic is a bare `pascal26:312:` with no file name, so a reader supplies
the file they invoked. `grep -rn '__doc__' --include=*.py` settles it: there are
ten in the tree, and `lekkerzeilen/__main__.py:312` is the **only one inside the
package** — the other nine are `argparse(description=__doc__...)` calls in
`tools/*.py`, which the closure never reaches.

## Why this is retention, not parsing

`compiler/pyparser.inc:41629`:

```pascal
  { A leading module docstring may precede the imports; consume it. }
  if (CurTok.Kind = tkString) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkNewline) then
  begin
    Next;
    PySkipNewlines;
  end;
```

The token is in hand and is dropped on the floor. Capturing it costs a global;
emitting it costs the eleven lines `sys.platform` already uses at
`compiler/pyparser.inc:12934`.

## The two hazards, and both are silent

**1. Absent docstring must be `None`, not `''`.** The call site is
`__doc__.strip()`. In CPython that raises `AttributeError` on a module with no
docstring; an empty string would `.strip()` happily and print a blank line —
a plausible wrong output with no diagnostic, which is the class this project
refuses over. Whatever is emitted for the no-docstring case, assert it: a
fixture whose module has **no** docstring is the positive control, and it must
be written, because the only arrangement anyone writes naturally is the one with
a docstring present.

**2. `__doc__` is per-module.** A single global holding "the docstring" will
hand an imported module the importer's text. The failure is a wrong string, not
an error. A fixture needs a module with a docstring importing a module with a
*different* docstring and printing both — and per the ordered-list rule, put the
interesting one where it does not pass by position: have the IMPORTED module's
docstring be the one read first.

## Expected-value collision to avoid

Do not let the fixture's expected docstring be something the machinery could
produce by doing nothing — not `''`, not the file name, not `None` spelled as a
string. Use a distinctive sentence.

## Closure position

Tenth wall of 2026-09-12. See
[[umbrella-lekkerzeilen-compiles-and-runs-under-nilpy]]; three of the last four
walls were library gaps, and this one is back to being a frontend gap.

## The line number is volatile and the defect is not (2026-09-12)

lekkerzeilen-a2 flagged it and it checked out: `lekkerzeilen/__main__.py` is
**modified on disk** in the owner's tree — an in-flight port of the platform
seam to pxx (`_pxx.py` +976, `_gl.py` +154, `gfx.py` stripped of ctypes, a new
`_vocab.py`). So:

    working tree   312:        print(__doc__.strip())
    HEAD           299:        print(__doc__.strip())

**The finding survives the caveat, and that is why it is written down rather
than left to a later re-measurement:** the construct is present in BOTH, and
both spellings of the module open with the same leading `Entry point.`
docstring, so the `__doc__` gap is real at HEAD and in the working tree alike.
Only the citation moves.

Quote the construct and the `--help` path. A line number against a tree somebody
else is editing is the classic stale pointer — it does not error, it points
somewhere.

## Resolution 2026-09-12 — implemented, and the ticket's own two hazards were both real

`__doc__` answers the module docstring. The closure moved off it; see below for
where it went.

**Both predicted hazards were real, and a THIRD one was not predicted.**

1. **Absent → `None`, never `''`** — as the ticket said. Measured: with `None`,
   `print(__doc__.strip())` raises `AttributeError`, byte-identical to CPython;
   with `''` every assertion in the fixture still passes and the program prints a
   blank line. The fixture asserts the `AttributeError` row for exactly that
   reason.
2. **Per-module** — REFUSED rather than answered. `ParsePyProgram` is the only
   routine that records a docstring (an imported module's leading string is an
   ordinary no-op expression statement), so the only value the emit site could
   hand an imported module is the MAIN module's. `CurrentUnitIdx >= 0` — the same
   seam `__file__` uses — raises instead. Control: a two-file probe where CPython
   answers `Module M own docstring.` confirms the main module's text really would
   have been a plausible wrong value.
3. **NOT PREDICTED, and it is the one that would have shipped a wrong string for
   this very app: CPython DEDENTS a docstring at compile time** (3.13+,
   `_PyCompile_CleanDoc`), so `__doc__` is *not* the literal and the ticket's
   prescribed emit pattern — the token's own span — is wrong for every indented
   docstring. `lekkerzeilen/__main__.py`'s docstring is indented **four**, and its
   `--help` is `print(__doc__.strip())`, which strips the ends and leaves all
   forty interior lines four columns over. Found by a fixture written with
   indentation in it; a flush-left fixture passes in both worlds.
   The rule was derived by MEASURING CPython 3.14, and two of its three clauses
   are not what a first reading gives: a **whitespace-only line is ignored** in
   the common-indent minimum (counting it gives 2 where CPython gives 6), and
   stripping is by **COLUMN** with the surplus re-materialised as **SPACES**, so
   `"""a\n\tb\n\t\tc\n"""` puts eight spaces before `c` rather than a tab.

**The ticket's prescription was also wrong about WHERE.** It named
`pasparser_expr.inc`'s identifier factor (via the `sys.platform` pattern). That
arm alone leaves `__doc__` undefined with the code sitting right there: a `.npy`
comes through **`pyparser.inc`**'s own identifier factor, which is why `__name__`
and `__file__` each appear in BOTH files. The arm is in both, as they are.

**What landed:** `PyModuleDocSeen/SOffset/SLen` in `defs.inc`; the recorder in
`ParsePyProgram` (dedent via `PyCleanDoc` + `StoredName`, so the node is an
ordinary pooled literal); the emit arm in both identifier factors; `PyMakeNone`
forward-declared in `compiler.pas` because the Pascal `tkNil` arm's `tyPointer 0`
answers `True` to `is None` and prints **`0`** under `repr` where CPython prints
`None` — measured, not assumed. Three fixtures, all diffed against CPython:
`test_nilpy_module_docstring`, `_absent`, `_dedent_columns`.

## Log
- 2026-09-12 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

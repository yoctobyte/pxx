---
track: N
prio: 70
type: feature
blocked-by: []
summary: "`__doc__` answers `undefined variable (__doc__)` and is the lekkerzeilen closure's wall at `__main__.py:312` as of 2026-09-12, with ALL of app.py now compiling. The module docstring is not missing from the compiler — it is deliberately THROWN AWAY: compiler/pyparser.inc:41629 consumes a leading module string literal with the comment \"A leading module docstring may precede the imports; consume it\" and keeps nothing. So the fix is to retain it, not to parse anything new, and `sys.platform` at compiler/pyparser.inc:12934 is the emit pattern to copy verbatim (AN_STR_LIT + StoredName + ASTTk := Ord(tyString)). TWO THINGS MAKE THIS BIGGER THAN IT LOOKS, both capable of a silent wrong value: a module with NO docstring must give `None`, not `''` — the call site is `print(__doc__.strip())`, which raises on None in CPython and would quietly print a blank line if we hand back an empty string; and `__doc__` is PER-MODULE, so an imported module reading its own `__doc__` must not see the main module's. Neither shows up as a compile error."
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

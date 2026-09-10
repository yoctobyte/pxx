---
slug: bug-n-staticmethod-is-not-a-value
track: N
type: bug
prio: 80
status: backlog
owner: ""
created: 2026-09-10
found-by: frankuser
tags: [nilpy, lekkerzeilen, values, builtins]
blocked-by: []
summary: "`clear = staticmethod(_unimplemented)` in a class body gave `undefined variable (staticmethod)`. FIXED 2026-09-10 (frankB). THIS TICKET WAS FILED WITH TWO FALSE CLAIMS AND BOTH CAME FROM A DIAGNOSTIC, NOT FROM CARELESSNESS -- it said staticmethod blocked BOTH modules of lekkerzeilen's portability seam and that bindings.py's KEY_ESCAPE row was its cascade. It blocked ONE: platform/__init__.py contains zero occurrences of `staticmethod` (measured: 0 vs 5 in _pxx.py) and KEY_ESCAPE did not clear. The evidence that manufactured the shared cause was that my census showed BOTH rows at `pascal26:31` -- and both were _pxx.py:31, because an error raised inside an IMPORTED module is printed with that module's line number and NO FILE NAME, so the reader supplies the file they invoked. Net effect of the fix: +1 module (_pxx.py, the only file in the corpus containing `staticmethod(`), cleared completely with nothing behind it. __init__.py moved one wall along, to _ctypes_backend.py's `import ctypes` reached via the branch taken when `import ctypes` SUCCEEDS -- a branch that is dead under pxx and resolved anyway."
---

# Measured 2026-09-10, compiler `b7745aaf0a59`, tree `3bebb551e`

```
lekkerzeilen/platform/__init__.py:31   undefined variable (staticmethod)
lekkerzeilen/platform/_pxx.py:31       undefined variable (staticmethod)
```

The idiom, from `_pxx.py` — a class used as a namespace whose members are
plain functions:

```python
class gl:
    clear_color = staticmethod(_unimplemented)
    clear       = staticmethod(_unimplemented)
```

# CORRECTED 2026-09-10 — what this ticket got wrong, and why

It was filed at prio 80 on the argument that it gated the whole `platform/`
package. That argument was false and the fix is worth +1 module, not 3.

**`platform/__init__.py` contains no `staticmethod`.** Measured: 0 occurrences
there, 5 in `_pxx.py`. **And `bindings.py`'s `KEY_ESCAPE` row did not clear** —
it was never a cascade of this ticket. `__init__.py`'s real wall is
`_ctypes_backend.py`'s `import ctypes`, reached through
`from . import _ctypes_backend` on the branch taken when `import ctypes`
SUCCEEDS. That branch is dead under pxx and the compiler resolves it anyway.

**The tell was in the census and two readers missed it: the two rows carried the
IDENTICAL line number, 31, and both were `_pxx.py:31`.** An error raised inside
an imported module prints as `pascal26:<n>:` with that module's line number and
**no file name**, so the reader supplies the file they invoked. Two unrelated
modules therefore reported one cause at one line, which reads exactly like a
shared dependency. frankB filed that separately
(`bug-n-an-error-inside-an-imported-module-is-reported-with-that-modules-line-number-and-no-file-name`,
prio 55) and it cost a second chase the same hour: post-fix, `__init__.py`
reports `pascal26:8: no unit named ctypes`, and line 8 of that file is the RST
prose ``` ``ctypes`` ``` — ten minutes spent testing whether a docstring was
being read as an import. It was not; the line belongs to another file.

**The import-position mechanism held exactly.** `staticmethod` sits at line 31
and there were four modules behind it that had never been reached, so a small
move was the prediction and a small move is what happened. The p80 was an
artefact of a diagnostic, not of the mechanism.

# Relationship to its two siblings — one concept, three doors

- `bug-n-os-environ-and-os-sep-are-not-values` — stdlib DATA attribute.
- `bug-n-a-stdlib-function-referenced-without-calling-it-is-not-a-value` —
  stdlib FUNCTION, uncalled.
- this one — a BUILTIN, uncalled.

**CORRECTED: that framing is right about two of the three and wrong about this
one.** `os.environ` and `math.sin` do share `PyIsStdlibMemberValue`. `staticmethod`
does not go near it — a builtin NAME is a separate mechanism, in the
`eval`/`setattr` chain (frankB, measured while fixing it). So do NOT try to fix
all three in one place; the first two are one job and this was another.

Also measured on the way past: `bug-n-os-environ-and-os-sep-are-not-values` is
**half stale** — `os.sep` and `os.linesep` have worked since `996bcf5a8`,
2026-08-29, the day after it was filed. What remains is `environ`, and it is a
different job: a MAPPING that both `in` and `.get`/`[]` must reach, not another
name in a list.

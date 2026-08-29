---
slug: bug-n-os-environ-and-os-sep-are-not-values
track: N
prio: 60
type: bug
status: backlog
blocked-by: []
summary: "`os.environ` and `os.sep` are not first-class values: `os.environ.get('X')` compiles but `'X' in os.environ` is `error: undefined variable (os)`. PyIsStdlibMemberValue recognises exactly three os members (seek_set/cur/end), so every DATA attribute of os fails while its functions work. Measured cost: it is the single largest wall in the reportlab probe — one 7-line file blocks 30 of 159."
---

# `os.environ` and `os.sep` are not values

- **Track N** (Nil-Python frontend — `compiler/pyparser.inc`'s stdlib-member
  dispatch, with the environment machinery already present in
  `compiler/builtin/pylib.pas`).
- Found 2026-08-28 by frankB (Track B) running the fourth-corpus probe of
  [[feature-b-a-fourth-corpus-to-test-whether-the-ladder-walls-generalise]].
  Measured against pin **v389**, md5 `0453ed506a14e464fd6c6cf0d81c6a55`.

## The boundary, measured

| spelling | result |
| --- | --- |
| `os.getcwd()` | compiles |
| `os.path.join('a','b')` | compiles |
| `os.getenv('HOME')` | compiles |
| `os.environ.get('HOME')` | **compiles** |
| `'HOME' in os.environ` | **error: undefined variable (os)** |
| `os.sep` | **error: undefined variable (os)** |

So this is not "os is missing" and not "environ is missing". **`os.environ` works
as the RECEIVER of a method call and fails as a VALUE.** Functions are fine;
data attributes are not.

## Cause

`compiler/pyparser.inc:11852`:

```pascal
else if base = 'os' then
  { os.SEEK_SET/CUR/END — the whence CONSTANTS, bare values not calls. }
  Result := (nm = 'seek_set') or (nm = 'seek_cur') or (nm = 'seek_end');
```

That is the whole list of `os` members `PyIsStdlibMemberValue` accepts. Anything
else in value position falls through and the base name `os` resolves to nothing,
which is why the diagnostic names `os` rather than the member — misleading, and
worth fixing alongside: the message should say which member was not found.

The data is already there for `environ`: `pylib.pas:12365` reads
`/proc/self/environ` into a table (`PyEnvLoad`), which is what backs the working
`os.environ.get(...)` path. What is missing is exposing it as a value — a dict
or a mapping-shaped object that `in` and iteration can reach.

## Why it is worth more than its size suggests

In the reportlab probe it is the **largest single wall: 30 of 159 files**, and
all 30 die on the same seven-line file:

```python
# reportlab/lib/__init__.py — the entire file
__version__='3.3.0'
import os
RL_DEBUG = 'RL_DEBUG' in os.environ
```

`reportlab.lib` is the package every chart, graphic and PDF module imports, so
one unsupported spelling in one leaf file gates a fifth of the corpus. `in
os.environ` and `os.environ['X']` are the two most common ways real code reads
the environment; `os.getenv` is the one we support and the less-used one.

`os.sep` is the same class and is cheap to add at the same time (a string
constant), along with `os.linesep`, `os.curdir`, `os.pardir`, `os.name`, `os.extsep`
and `os.altsep` — all constants, all in value position, all currently failing.

## Fix sketch

Two independent pieces, either useful alone:

1. **The constants** — `sep`, `linesep`, `curdir`, `pardir`, `extsep`, `altsep`,
   `name`. Add to the `base = 'os'` list and return a string literal node, the
   way `seek_set` already returns an int literal. Small and mechanical.
2. **`os.environ` as a value** — a mapping over the existing `PyEnvLoad` table
   supporting `in`, `[]`, `.get()` and iteration. The data is already read; this
   is a shape, not a syscall.

## Gate

```python
import os
print('HOME' in os.environ, os.sep)
```
compiles and matches CPython, and `library_candidates/reportlab/src/reportlab/lib/__init__.py`
compiles — after which the probe's 30-file wall should collapse. Track N's gate
(`test-nilpy` green + self-host byte-identical) plus an `.npy` regression row.

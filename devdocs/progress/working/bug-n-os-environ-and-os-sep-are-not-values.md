---
slug: bug-n-os-environ-and-os-sep-are-not-values
track: N
prio: 60
type: bug
status: working
blocked-by: []
summary: "`os.environ` is not a first-class value: `'X' in os.environ` is `error: undefined variable (os)`, while `os.environ.get('X')` compiles. RE-MEASURED 2026-09-10 at compiler `98b6545b4652` and THE SLUG IS HALF STALE: `os.sep` WORKS -- it prints `/` -- and so does `os.linesep`. `PyIsStdlibMemberValue` gained both at `996bcf5a8` on 2026-08-29 -- the DAY AFTER this ticket was filed -- and this summary was never updated, so a reader picking this up would spend the first measurement discovering that half of it is done. What is left is `environ` specifically, which is not a constant string but a MAPPING, so it needs a value the `in` operator and `.get`/`[]` can both reach -- a different job from adding a name to that gate's list. SIBLING BUT NOT THE SAME GATE -- re-measured 2026-09-10 while taking both as a group: PyIsStdlibMemberValue is consulted for `sys` and `os` and nothing else, and was never in math.sin's path, so that ticket's fix (FindProcInUnit and the qualified-member value door) does nothing here. What DID land is the diagnostic: `f = os.getcwd` said `undefined variable (os)` and now names the shim and the workaround. `os.environ` as a mapping and the remaining os constants are untouched and are what is left; the third door frankuser grouped with them, `staticmethod`, turned out NOT to share it -- a builtin name is a separate mechanism and was fixed separately on 2026-09-10. Original measured cost stands: it is the single largest wall in the reportlab probe, one 7-line file blocking 30 of 159."
owner: frankB
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

# Re-measured 2026-09-10 at compiler `de51b67ba86b` — PARKED, not resolved

Taken as a group with
[[bug-n-a-stdlib-function-referenced-without-calling-it-is-not-a-value]] on that
ticket's own instruction (*"whoever takes either should look at both: a gate
that enumerates members is the mechanism"*). **The shared-mechanism premise did
not survive the measurement, so the two are not one fix.**

`PyIsStdlibMemberValue` is consulted for `sys` and `os` and nothing else. It was
never in `math.sin`'s path at all — that reaches the qualified-member value door
and `FindProcInUnit`, which is where its fix landed. So this ticket's remaining
work is genuinely its own.

## What DID change here, and it is only the diagnostic

`f = os.getcwd` said `undefined variable (os)` — a message blaming the import
for a module that resolves perfectly, one line under a working `os.getcwd()`.
It now says that `os.getcwd` is a compiler-provided shim reachable only as a
CALL, and names the one-line lambda that works. That is the honest half of this
ticket's complaint about the diagnostic (*"the message should say which member
was not found"*), reached from the other side.

## What did NOT change, and is what is left

- **`os.environ` as a value.** Unchanged. It is a MAPPING, not a name in a
  table: `in`, `[]` and iteration all have to reach it, so it needs a shape
  built over the existing `PyEnvLoad` data, not an entry added to a list. This
  ticket's own fix sketch already says so and is still right.
- **The `os` CONSTANTS beyond `sep`/`linesep`** — `curdir`, `pardir`, `name`,
  `extsep`, `altsep`. Still absent. Still the small mechanical half.

The `reportlab` cost figure in the body above (30 of 159 files on one 7-line
`__init__.py`) is untouched by anything here: `'RL_DEBUG' in os.environ` is the
mapping half, not the diagnostic.

Left in `working/` with `owner: frankB` as ATTRIBUTION for this measurement, not
as a claim — free to take, and the measurement above is the part that saves the
next reader a session.

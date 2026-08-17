---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`Warning`, `UserWarning` and `DeprecationWarning` do not exist in NilPy, so `class DataLossWarning(UserWarning)` will not compile. They are BUILTINS, named bare by calling code, so no mimic_warnings shim can supply them — this blocks the warnings shim and 16 non-test html5lib call sites."
status: done
owner: frank3
---

# The builtin `Warning` exception hierarchy is missing

- **Type:** bug (missing builtin) — **Track N**. Likely `compiler/builtin/**`,
  which means it **needs a pin** and is coordinator-scheduled.
- **Found:** 2026-08-17 by frank3 (Track B), measuring the premises of
  [[feature-nilpy-six-and-warnings-shims]] before writing that shim.
- **Measured against:** `pinned` **v344**. Not re-checked at HEAD — Track B
  cannot rebuild the compiler. Re-measure before working it.

## Repro

```python
print(Warning, UserWarning, DeprecationWarning)
```

```
pxx:     pascal26: error, near: print  Warning >>>  UserWarning
CPython: <class 'Warning'> <class 'UserWarning'> <class 'DeprecationWarning'>
```

## Why a shim cannot paper over it

These are **builtins**, not members of `warnings` — calling code names them
bare, and subclasses them:

```python
# html5lib/constants.py:2940
class DataLossWarning(UserWarning):
    pass
```

So `mimic_warnings` cannot supply them however it is written, and a
`mimic_warnings` shipped without them would resolve `import warnings` and then
fail one line later at the first category argument. That is worse than the
honest missing module and violates the T1 rule in
`devdocs/dev/python-compat-tiers.md` (a shim states its subset and fails loudly
rather than approximating).

## Blast radius, measured not estimated

Every `warnings.warn` call in non-test html5lib code passes a category:

| category | sites |
| --- | --- |
| `DataLossWarning` | 14 |
| `DeprecationWarning` | 2 |

The 14 are indirect — they need `UserWarning` only so that `DataLossWarning` can
be *declared* — so all 16 sit behind this one gap.

## Note on scope

The full CPython warning tree is large (`SyntaxWarning`, `RuntimeWarning`,
`BytesWarning`, …). What is measured as load-bearing here is three names:
`Warning`, `UserWarning`, `DeprecationWarning`. Whether to add the three or the
whole tree is a judgement for whoever owns the builtin exception table — the
rest are cheap once the base exists, and a partial tree that silently misses a
name is the failure mode worth avoiding.

## Gate

`class D(UserWarning): pass` compiles, `warnings.warn(msg, D)` accepts it, and
the three names print as classes like CPython.

## 2026-08-17 (frank3) — working. Premises re-measured on the current tree.

Assigned to Track B rather than N because the fix is **runtime-library ground**:
the exception table lives in `compiler/builtin/pylib.pas`, not in the NilPy
frontend files, and is disjoint from the `parser.inc` / `ir*.inc` work Track A
holds tonight. No shared-core file is touched.

### Re-measured, unchanged

```
print(Warning, UserWarning, DeprecationWarning)
  -> pascal26:1: error: undefined variable (Warning)
```

while `Exception`, `ValueError`, `TypeError`, `RuntimeError` and `KeyError` all
resolve. So the gap is exactly the Warning subtree and nothing adjacent.

### Where it goes, and why it is not a shim

`compiler/builtin/pylib.pas` already carries the whole builtin exception tree as
a flat table of `X = class(Y) end;` — `OSError`, `LookupError`, `RecursionError`,
the `ConnectionError` family, the `IOError = OSError` alias. The Warning names
are peers of those, and they are **builtins named bare by calling code**
(`class DataLossWarning(UserWarning)`), which is what makes a `mimic_warnings`
structurally unable to supply them.

### Scope: the whole tree, not the three that are load-bearing

The earlier note left this open ("whether to add the three or the whole tree is
a judgement"). Resolved: **all twelve**, read off CPython 3.12's `builtins`
rather than from memory —

`Warning(Exception)`, then `UserWarning`, `DeprecationWarning`,
`PendingDeprecationWarning`, `SyntaxWarning`, `RuntimeWarning`, `FutureWarning`,
`ImportWarning`, `UnicodeWarning`, `BytesWarning`, `ResourceWarning`,
`EncodingWarning`, all deriving directly from `Warning`; none nest.

A partial table is the worse failure mode here and the ticket said so: the
missing name does not announce itself, it surfaces later as `undefined variable
(ResourceWarning)` inside somebody's library — and each addition costs another
round trip through a pin, which is a repo-wide lock.

### Landed

`compiler/builtin/pylib.pas` gains the twelve names beside the existing builtin
exception table. Verified against the freshly built compiler:

```
print(Warning, UserWarning, DeprecationWarning)
  -> <class '__main__.Warning'> <class '__main__.UserWarning'> <class '__main__.DeprecationWarning'>
```

`test/test_nilpy_warning_hierarchy.npy` + `.expected`, wired into `test-nilpy`.
It **runs unmodified under CPython and the two outputs are byte-identical**, so
the expectations come from the oracle rather than from memory. It asserts the
tree shape (`Warning` under `Exception`, all eleven others directly under
`Warning`), that they are SIBLINGS rather than a chain
(`issubclass(DeprecationWarning, UserWarning)` is False — the easy thing to get
wrong in a hand-written table), subclassing (`class DataLossWarning(UserWarning)`,
the shape html5lib actually uses), raise/catch at each level, and passing the
class itself as an argument, which is what `warnings.warn(msg, Category)` needs.

All twelve are named individually rather than looped over a list. Two reasons:
`issubclass()` here takes class NAMES and refuses a variable holding a class
(clear diagnostic, not a crash — my first draft hit it), and naming them makes a
missing one a **compile error in this file** rather than a silent gap.

### Note for whoever picks up the `warnings` shim

This unblocks the *categories*, not the module. `import warnings` still needs
`mimic_warnings` — `warn(msg, category)` writing to stderr, with
`simplefilter`/`catch_warnings`/`resetwarnings` as no-ops. That is the remaining
half of [[feature-nilpy-six-and-warnings-shims]] and is now genuinely writable,
which it was not this morning.

## Log
- 2026-08-17 — resolved, commit PENDING-COMMIT.

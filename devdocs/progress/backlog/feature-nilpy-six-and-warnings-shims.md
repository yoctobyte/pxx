---
track: B
prio: 45
type: feature
---

# `mimic_six` and `mimic_warnings` — the biggest lever for the library campaign

Measured 2026-08-09 by compiling all 48 `.py` files of `webencodings`,
`tinycss2` and `html5lib` as source and ranking what stopped each one. After the
language walls were fixed (backslash continuations, relative imports,
`class C(object)`), **every remaining failure is a missing module**, and the
distribution is lopsided:

| missing module | files blocked |
| --- | --- |
| **`six`** | **11** |
| `xml.dom` / `xml.sax` | 5 |
| **`warnings`** | **3** |
| `genshi` (an optional treewalker) | 2 |
| `codecs` | 2 |

## Why `six` is the cheap win

`six` is a pure-Python Python-2/3 compatibility shim, and on a Python-3-only
dialect almost every one of its names is trivially true:

- `PY2 = False`, `PY3 = True`
- `text_type = str`, `binary_type = bytes`, `string_types = (str,)`
- `integer_types = (int,)`, `class_types`, `unichr = chr`
- `iteritems(d)` → `d.items()`, `itervalues`, `iterkeys`
- `with_metaclass` / `add_metaclass` — the two that are NOT trivial

The last pair is the honest caveat: they are metaclass machinery, which NilPy
does not have. Real usage in html5lib should be checked before deciding whether
to implement them, alias them to a no-op, or **refuse them by name** — the last
being much better than a silently wrong class, and consistent with how the rest
of the dialect walls unsupported features.

`warnings` is smaller still: `warn(msg)` printing to stderr and
`simplefilter`/`catch_warnings` as no-ops covers what a library does with it.

## Note on how the file counts read

A file is rejected at its FIRST unavailable import, so one missing module hides
however many gaps sit behind it. These counts are therefore a lower bound on the
unblock, not an estimate of the remaining work — landing `six` will reveal the
next layer, which is the point of doing it.

## Gate

`make lib-test`, plus re-running the 48-file scan and recording the new counts
on `feature-nilpy-thirdparty-libraries-as-targets` (the scan is a few lines of
shell; the ranked-walls table there is the format to update).

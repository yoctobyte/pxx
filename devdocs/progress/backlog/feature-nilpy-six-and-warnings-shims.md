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

## Measured surface, 2026-08-09 — every `six` name html5lib/tinycss2 actually import

Not a guess at `six`'s API: this is `grep "from six" ` over the real sources, so
the shim can be scoped to exactly this and nothing else.

| name | import sites | what it is on Python 3 |
| --- | --- | --- |
| `text_type` | **8** | `str` |
| `PY3` | 2 | `True` |
| `binary_type` | 1 | `bytes` |
| `string_types` | 1 | `(str,)` |
| `unichr` | 1 | `chr` (imported as `from six import unichr as chr`) |
| `viewkeys` | 1 | `d.keys()` |
| `with_metaclass` | 1 | **metaclass machinery — the hard one** |

Plus three sites importing from **`six.moves`**, which is a different problem:
`urllib_parse` (sanitizer), `http_client` and `urllib` (`_inputstream`). Those
are stdlib re-exports, so they need `urllib`/`http.client` to exist at all — not
part of this shim.

**So the split is 12 trivial import sites against 2 hard ones.** Six of the
seven names above are one-line aliases; `with_metaclass` appears exactly once,
in `html5parser.py`. That single file is what decides whether the shim gets
html5lib's parser or only its periphery — worth looking at `html5parser.py`'s
use of it before choosing between implementing, no-opping, and REFUSING by name.

`viewkeys` is a small trap worth naming: it is a FUNCTION (`viewkeys(d)`), not a
method, so aliasing it to `dict.keys` needs the unbound-method-as-a-value
support that `feature-nilpy-str-surface-gaps-2026-08-09` records as missing
(`sorted(xs, key=str.lower)` fails the same way). A one-line `def viewkeys(d):
return d.keys()` sidesteps that entirely.

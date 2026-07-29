---
track: N
prio: 30
type: feature
---

# Measured stdlib coverage: json and re are solid; os, time and math.fabs are absent

A sweep of the modules a small script typically reaches for, each a handful of
representative calls, diffed against CPython:

| module | result |
| --- | --- |
| `json` | **exact** — `dumps` of a dict, `loads` and subscript |
| `re` | **exact** — `match` with groups, `sub` with a class |
| `math` | `sqrt`, `floor`, `ceil`, `pi` fine; **`fabs` undefined** |
| `os` | **`undefined variable (os)`** — no `os.path.basename`, no `os.path.exists` |
| `time` | **`no overload of time matches these arguments`** — `time.time()` |
| file I/O | `open(...)` binds something typed TPyList, so `.read()` fails with `TPyList has no method read` — the known [[feature-nilpy-file-io-and-comprehensions]] |

json and re being exact is the notable half: those are the two hardest to fake
and the two most likely to appear in a real script.

The gaps are all compile-time, so nothing computes a wrong answer. Priority is
low deliberately — the fix is per-function plumbing with no design content, and
`os.path` is the only one with real surface area. `math.fabs` is one line
(`abs` on a double).

One thing worth checking while doing this: `open()` binding to TPyList suggests
the name resolves to something unrelated rather than being absent, which is the
shape [[bug-nilpy-stdlib-name-binds-pascal-unit]] describes.

## Gate

`make test-nilpy` + self-host byte-identical, plus the table above.

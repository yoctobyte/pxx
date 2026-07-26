---
summary: "nilpy: re module (match/search/sub/findall/fullmatch/compile) over the regex engine"
type: feature
track: N
prio: 50
blocked-by: [feature-lib-regex-engine]
---

# nilpy: `re` module

- **Type:** feature (Nil-Python frontend, stdlib surface) — **Track N**
- **Status:** done
- **Opened:** 2026-07-26 — first wall compiling songformatter
  ([[feature-demo-songformatter-pxx-target]]): `import re` fails with
  `uses: unit source not found: re`.

## Motivation

`import re` is the first thing that stops songformatter's smallest module
(`key_analysis.py`) from compiling, and it will stop most real Python. Backed by
[[feature-lib-regex-engine]] — this ticket is only the frontend surface, the same
shape as the existing `os.*` dotted-call mapping in `pyparser.inc` (`os.path.join`
-> `pyos_path_join`).

## Surface

Module-level: `re.match`, `re.search`, `re.fullmatch`, `re.sub`, `re.findall`,
`re.compile`, and the flags (`re.X`/`re.VERBOSE`, `re.I`).

Match objects: truthiness (songformatter does `bool(re.match(...))` and
`is not None`), `.group(n)`, `.groups()`.

Compiled patterns: the same methods as the module functions.

## Gate

`make test-nilpy` green with a `.npy` case diffed against CPython over the
surveyed songformatter patterns, + `--tier quick` + self-host byte-identical.

## Log
- 2026-07-26 — resolved, commit ca4dac8d.

## Update (2026-07-26) — landed, commit `ca4dac8d`

`lib/rtl/re.pas`, named `re` so NO frontend change was needed: `import X` becomes
`uses X`, so the unit name IS the Python module name, and `re.match(p, s)` resolves
by ordinary unit qualification (the flat `match(p, s)` works too). No entry in
pyparser.inc's dotted-call table, no pylexer special case, and no `-Fu` flag —
lib/rtl is already on the default search path when the compiler runs from the repo
root.

Semantics were PROBED, not assumed, before the design was fixed: a class instance
is truthy, nil is falsy, `is None` works on nil, and methods dispatch on a
returned instance. Hence a match is a TMatch or nil, which gives Python's `if m:`
for free.

Surface: match/search/fullmatch/sub/findall/compile/escape, flags under both
spellings, `m.group(n)`/`m.start(n)`/`m.stop(n)`, and a compiled TPattern accepted
as the first argument to the module functions (CPython allows this too).

Deliberate differences, both documented in the unit header: `findall` with 2+
groups yields a list per match (no tuple type in NilPy; indexing identical), and
`m.end()` is `m.stop()` because `end` is a Pascal keyword. Offsets are 0-based
with -1 for a non-participating group, as CPython.

Gate: `test/test_nilpy_re.npy` wired into both `test-nilpy` variants, expectation
= CPython's own output for the same script (diffed identical). `make test-nilpy`
green, 135 compiles, run against the pinned stable — its default `$(COMPILER)`
rule currently dies earlier on the self-host fixedpoint `cmp`, which reproduces on
a clean tree and is [[chore-makefile-selfhost-iterate-to-convergence]].

---
summary: "nilpy: re module (match/search/sub/findall/fullmatch/compile) over the regex engine"
type: feature
track: N
prio: 50
blocked-by: [feature-lib-regex-engine]
---

# nilpy: `re` module

- **Type:** feature (Nil-Python frontend, stdlib surface) — **Track N**
- **Status:** backlog
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

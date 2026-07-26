---
summary: "regex engine library — backtracking matcher, the substrate for nilpy's re module"
type: feature
track: B
prio: 50
---

# regex engine library

- **Type:** feature (library) — **Track B** (file-owned)
- **Status:** backlog
- **Opened:** 2026-07-26 — surfaced compiling songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]): `import re` is the FIRST wall, and
  pxx has no regex engine anywhere (no `lib/**` unit, no RTL support).

## Motivation

`re` is not a niche import — it is in the standard vocabulary of real Python, and
of real C/Pascal programs too. There is currently nothing to bind a nilpy `re`
module to, so the engine is the substrate and comes first. Language-neutral by
design, like every Track B library: one engine, consumed by nilpy's `re`
([[feature-nilpy-re-module]]) and directly usable from Pascal.

## Surface (sketch)

A `TRegex` compiled-pattern object plus match results:

- `Compile(const pattern: AnsiString; Flags: TRegexFlags): TRegex`
- `Match` (anchored at start), `Search` (first position), `FullMatch`
- `FindAll` (all non-overlapping matches), `Replace` (with `\1` group refs)
- group access: count, text, start/end offsets

Feature subset songformatter actually needs, all 14 of its call sites surveyed:

- character classes `[A-Ga-g]`, `[b#]`, negation, escapes in classes,
  literal ranges including `\x00-\x1f`
- alternation `IV|IX|I|V|X`, groups `(...)`, non-capturing `(?:...)`
- quantifiers `*` `+` `?`, non-greedy `.*?`
- anchors `^` `$`, escape classes `\d` `\s` `\\`
- the `VERBOSE`/`re.X` flag (one songformatter pattern is a commented multi-line
  pattern)

Backtracking is the right shape here: patterns are short, subjects are single
chord/lyric lines, and it keeps group capture and non-greedy semantics simple.

## Gate

Track B: build with `$(PXX_STABLE)`, never rebuild the compiler. `make lib-test`
green with a test comparing the engine against expectations recorded from
CPython's `re` for the surveyed patterns.

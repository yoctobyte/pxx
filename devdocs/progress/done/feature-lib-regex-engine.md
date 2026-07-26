---
summary: "regex engine library — backtracking matcher, the substrate for nilpy's re module"
type: feature
track: B
prio: 50
---

# regex engine library

- **Type:** feature (library) — **Track B** (file-owned)
- **Owner:** claude-b-opus5
- **Status:** done
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

## Update (2026-07-26) — landed

`lib/rtl/regex.pas` + `test/lib_regex.pas`, wired into `make lib-test`. 61 checks,
all green, and every expectation cross-checked against CPython's `re` for the same
pattern/subject pairs (a hand-written expectation WAS wrong: the songformatter
chord class holds lower-case 'b' but not upper-case 'B', so `G/B` is correctly
rejected — CPython agrees).

Two engineering notes worth keeping:

- **Quantifiers and alternation rebuild their region, they do not insert into it.**
  The first cut made room for a split by shifting the program and relocating every
  target `>= at`. That cannot work: a target pointing exactly AT the insertion
  point is ambiguous. A preceding `x?` holds a forward skip-target that must keep
  pointing at the newly inserted split, while a `(a+)?` body holds a backward
  target to the region start that must move. One rule cannot serve both, and it
  showed up as `[A-G][#b]?(?:maj7|m7)?` silently failing to match `Am7` — a
  wrong ANSWER, not a crash. Both now lift the region out (ReTakeBody) and
  re-emit it (ReAppendBody) with a single delta, which is unambiguous.
- **The pinned compiler NESTS `{ }` comments.** A comment containing a brace, even
  inside quotes as in `{ '{' }`, stays open until a later `}` — which was found
  inside a string literal 30 lines down, reported as "unexpected character" there.
  Worth knowing for any Track B file that documents brace syntax.

Not implemented, and reported by ReCompile as an error rather than mis-matched:
lookaround, in-pattern backreferences, named groups, possessive quantifiers,
unicode classes.

**`make lib-test` has a PRE-EXISTING red** unrelated to this work, now filed as
[[feature-rtl-month-day-name-arrays]]: the `lib_synapse` step dies on
`undefined variable (ShortMonthNames)`. Reproduced on a clean tree with
`git stash -u`. The regex step itself passes inside `lib-test`, before that point.

## Log
- 2026-07-26 — resolved, commit 1e29abdf.

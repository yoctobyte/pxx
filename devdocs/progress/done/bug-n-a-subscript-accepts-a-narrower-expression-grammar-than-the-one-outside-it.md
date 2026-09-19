---
slug: bug-n-a-subscript-accepts-a-narrower-expression-grammar-than-the-one-outside-it
track: N
type: bug
prio: 70
status: done
owner: frankH
created: 2026-09-19
found-by: frankuser
tags: [nilpy, parser, tsp, demo]
blocked-by: []
summary: "Inside `[...]` the NilPy parser accepts a NARROWER expression grammar than the one it uses everywhere else: `d[unit or \"s\"]` is `expected ']' before 'or'` and `d[\"a\" if f else \"b\"]` is `expected ']' before 'if'`, while the IDENTICAL expression one line earlier (`k = unit or \"s\"`) compiles and runs. Two expression parsers, one of them wired into the subscript. Measured on That Space Program 2026-09-19: this is the FIRST wall in 16 of 61 modules, the single largest — AND RE-MEASURED 2026-09-19 THERE IS EXACTLY ONE SITE. All 16 rows report `pascal26:195:`, which is `tsp/timebase.py:195` (`total += float(num) * _DURATION_UNITS[unit or \"s\"]`) — an error raised inside an IMPORTED module prints with that module's line number, so the reader supplies the file they invoked. A fixed-string search over the whole corpus finds that one line and nothing else; the other `[... or ...]`/`[... if ...]` hits in `tsp/` are LIST COMPREHENSIONS, which are not this bug. So 16 is the size of timebase.py's import graph, not a count of sites, and three of the 16 (anchor, moons, reference) do not name timebase at all — they reach it transitively. The fix is worth 16 modules ADVANCING and is one line of parser; it is not sixteen call sites. (The instrument that first said "zero of 16 contain the construct" was a broken regex answering 0 for the file that demonstrably does contain it — caught by a positive control, and recorded here so nobody re-derives it.) READ THE CAVEAT TOO: a count of modules blocked is NOT a count of work, and in this repo clearing the largest wall has moved units-compiling by ZERO four times."
---

# `or` and a conditional expression are refused inside a subscript and accepted outside it

Found by a per-module sweep of **That Space Program** (`~/tuxspaceprogram`,
official name *That Space Program*, not the folder name), 2026-09-19, compiler
`28067ea1d2f3`.

## Minimal, with the control beside it

```python
d = {"s": 1, "m": 60}
unit = ""
k = unit or "s"      # OK, compiles and prints s
print(d[unit or "s"])  # pascal26:3: error: expected ']' before 'or'
print(d["a" if f else "b"])  # pascal26:3: error: expected ']' before 'if'
```

**The control is the point:** the same `or` expression bound to a name one line
earlier compiles and runs. So this is not "we do not support `or`" — it is the
subscript using a different, narrower expression parser.

## Real site

`tsp/timebase.py:195` — `total += float(num) * _DURATION_UNITS[unit or "s"]`.
The `x or default` subscript is ordinary Python and appears throughout the
corpus.

## What this is NOT evidence for

**Fifteen modules hit this FIRST. That is not fifteen modules' worth of work
unblocked.** The census is first-failure, so every wall behind this one is
invisible, and this repo has four dated cases where clearing the largest wall
moved the compiling count by zero. **Record what you expect BEFORE re-running
the sweep**, or the result is uninterpretable either way.

## Likely shape, not verified

The grep to run first is for the OTHER spelling's handler: find where a
subscript parses its index and compare it against the general expression entry
point, rather than grepping for `or`. Same shape as the `$cfnptr`/`$cfntype`
and `ParseConstSection`/`ParseVarSection` pairs — two doors, one wired.

## 2026-09-19 — re-measured: 16 modules, ONE site

frankh-3f found it first, from the other end: it reported `universe.py:195` and
then noticed the run printed `in: tsp/timebase.py` at the same line, so
`universe` and `ascent` are one wall and not two.

Checked across the whole census. **All 16 first-failure rows read
`pascal26:195:`.** That is the diagnostic naming an IMPORTED module's line with
no file name — the class already written up in CLAUDE.md, where two modules
failing at line 31 read as one shared dependency and the fix was worth one
module of three. Here the shared cause is REAL, and the count is still not a
count of work:

```
$ grep -rn 'unit or "s"' --include=*.py tsp/
tsp/timebase.py:195:   total += float(num) * _DURATION_UNITS[unit or "s"]
```

One line, one file. Three of the sixteen (`anchor.py`, `moons.py`,
`reference.py`) never name `timebase` — they reach it transitively.

**The broader search needs its own caveat.** A pattern for "a bracket containing
` or `/` if `" matches 11 files, and almost every hit is a LIST COMPREHENSION
(`[x for x in y if cond]`), which parses fine. `commentary.py:192`'s
`max([...] or [launch])` is an `or` inside a CALL, not a subscript. The subject
of this ticket is a conditional expression in SUBSCRIPT position, and there is
one.

**Instrument note, recorded so it is not re-derived.** The first pass at this
used `grep -cE '\[[^]]*\b(or|if)\b[^]]*\]'` inside a shell loop and answered
**0 for every file, `timebase.py` included** — the file that demonstrably
contains the construct. The `\b` did not survive the quoting. It was caught by
running the positive control (does the pattern find the KNOWN site?) before
believing the zero, and it is the guard-that-cannot-fail shape exactly: a
census answering 0 everywhere reads as a clean, confident finding.

**What this changes about the ticket:** nothing about the defect, which is
unchanged and real. The VALUE is unchanged too — fixing it advances 16 modules
to their next wall. What changes is the SIZE: this is one parser fix against one
call site, not sixteen sites, and nobody should scope it as the latter.

## 2026-09-19 — FIXED (frankH)

The seam was one call, not one line of grammar: `ParsePropIndexArgs`
(pasparser_call.inc) parsed each index with Pascal's `ParseExpr`. The call-
argument door already had the NilPy hook, `ParseArgExpr` (pyforwards.inc:
`PyParseBoolExpr` under NilPy, `ParseExpr` otherwise), and the index now uses
it. `or`, `and`, `in` (Python's meaning) and the conditional expression all
work inside `[...]`, on name, attribute and function-local receivers, and as
assignment and augmented-assignment targets. Slices, literal receivers and
`not` were already reached through other paths and still work. Pascal cannot
move: without NilPy the hook IS `ParseExpr`.

Test: test_nilpy_subscript_index_is_a_full_expression, whose .expected is
CPython 3.14.4's output. The pinned compiler refuses it at its first `or`.

### TSP census, with the expectation written BEFORE the re-run

Population: every `tsp/**/*.py` outside `__pycache__` at TSP 13eb601, 66
files, one compile each from the TSP root, first `error:` line recorded. This
is NOT the 61-module set above, which I could not reproduce (60 excluding
`__init__`/`__main__`), so compare within a row, not across the two.

| compiler | OK | first wall at timebase.py:195 |
| --- | --- | --- |
| 8c314084d635 (pxx 531d1c843, before) | 18 | 22 |
| c101486bdd1e (this fix) | 20 | 0 |

Written beforehand: *all 22 move past 195; OK rises by few, point estimate
~21, because they share one dependency and whatever is behind 195 walls them
again as a group.* Measured: all 22 moved; OK went up by two (`timebase`,
`earth`). The other 44 rows are byte-identical before and after. Where the 22
went next:

- 14: `tsp/ephem/__init__.py:17`, the DIAMOND refusal on
  `class EphemerisMissing(EphemerisError, FileNotFoundError)`.
- 3: `tsp/orbit.py:217`, "expected newline after statement".
- 2: `tsp/parts.py:73`, "expected expression".
- 1: `director.py:37`, `@dataclass(frozen=True)`.
- 2: OK.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit f96cbaab9.

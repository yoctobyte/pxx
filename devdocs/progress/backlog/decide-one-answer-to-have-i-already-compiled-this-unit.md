---
track: U
prio: 40
type: decide
blocked-by: []
summary: "Three tickets in three lanes are all 'a compilation unit got processed twice', served by three unrelated mechanisms: unit-NAME keying (Pascal/NilPy), an @cpath: key space (path-form C units), and preprocessor include-guard visibility (C headers). Two is a smell, three is a design flaw. Question for the user: does 'have I already compiled this translation unit?' deserve ONE answer, or are three correct-in-their-own-lane answers the right shape?"
---

# Does "have I already compiled this unit?" deserve one answer?

- **Type:** decision (Track U) — no files, no gate.
- **Filed by:** Track N (frank2), 2026-08-17, out of
  [[bug-a-a-python-module-s-identity-is-its-name-not-its-file]]. Filed rather
  than answered because it is a design call about shared core structure, and
  guessing it wrong would be invisible afterwards.

## Why this is being asked now

It crosses the repo's own stated threshold. `devdocs/dev/root-cause-over-microfix.md`
says to count how many mechanisms serve one concept — **two is a smell, three is
a design flaw**. There are three:

| mechanism | lane | what it keys on | ticket |
| --- | --- | --- | --- |
| `CompiledUnits[]` / `guardIdx` | A (Pascal, NilPy) | the unit **NAME** | [[bug-a-a-python-module-s-identity-is-its-name-not-its-file]] |
| `@cpath:` key space | A/C (path-form C units) | the path **TEXT** | (the fix for `bug-c-uses-path-basename-collides-with-enclosing-unit-name`) |
| preprocessor include guards | C (headers) | macro-table **visibility** | [[bug-c-header-with-a-body-compiles-twice-across-the-macro-reset]], [[bug-c-string-h-compiles-stdlib-c-twice]] |

Each is correct in its own lane. **None is aware of the others**, and each has
produced at least one bug where a file was processed twice.

**These are genuinely different roots** — that was checked, not assumed, before
filing: the C ones are include-guard visibility lost across a macro-table reset,
not unit-identity keying. So this is NOT a proposal to merge three tickets. It
is the observation that three separate mechanisms answer one question, which is
a different and larger claim than any of them.

## The evidence that prompted it

A `.py` module reached by two import spellings compiles twice, because `sub` and
`pkg_sub` are different NAME keys for one FILE. Its body then runs twice where
CPython guarantees once — duplicated registry population, and two distinct
copies of every class so `isinstance` across them fails. The visible output
stayed correct throughout, which is why it went unnoticed.

## The fork

**Option A — leave it as three.** Each lane keeps its own answer; fix
[[bug-a-a-python-module-s-identity-is-its-name-not-its-file]] narrowly by adding
a resolved-path key beside the name key, exactly as `@cpath:` already does.
Cheap, local, no cross-lane risk. Cost: the fourth instance of this class is
already predictable, and the `@cpath:` precedent shows the pattern is to add a
key space per surprise.

**Option B — one identity for a translation unit**, resolved-file based, that
every frontend's "already compiled?" check consults. Deletes cases rather than
adding them, and would have prevented all three. Cost: it touches `parser.inc`'s
load path — the thing every lane's gate depends on — and the C preprocessor half
may not fit the same key at all (a header's guard is about *visibility of a
macro*, not about identity of a file, so it may be a genuinely different
question wearing a similar symptom).

**Option C — decide it is not one concept.** Defensible: "have I loaded this
unit" and "is this header's guard visible" may only look alike. If so, say so
once and record it, so the next person who notices the resemblance does not
re-open this.

## Recommendation

**Option A now, Option C recorded, and B only if a fourth instance appears.**
The immediate bug needs a narrow fix that is not blocked on this question, and
the C half is the weakest part of the analogy — I would not force it into a
shared mechanism on the strength of a shared symptom, which is the same
over-merging error the sibling check was careful to avoid in the other
direction.

But this is a judgement about how much unification the core should carry, and
that is the user's call, not a worker's. The evidence is above; the answer is
not obvious from it.

## What is NOT blocked on this

[[bug-a-a-python-module-s-identity-is-its-name-not-its-file]] should be fixed
regardless — it is a live bug with a known live exposure (`mimic_codecs`
registers at import time, i.e. exactly the double-run shape). This decision only
governs whether that fix is narrow or the start of a unification.

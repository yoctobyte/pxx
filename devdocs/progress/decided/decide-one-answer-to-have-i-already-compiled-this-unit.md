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

---

## DECIDED 2026-08-19 (user) — B for identity, C for the preprocessor half

**User: "B seems the obvious choice. And for the C language it's hardly relevant since C
typically uses header guards already."**

That splits the three mechanisms **2-and-1**, which is a sharper answer than the ticket's
own fork offered — B and C were presented as alternatives and are in fact orthogonal.

### B — one resolved-file identity, absorbing TWO mechanisms

`CompiledUnits[]` name-keying **and** the `@cpath:` key space both answer "is this the
same translation unit?", both live in `ParseUsesUnit` in `parser.inc`, and both got there
by adding a key space per surprise. They unify on resolved-file identity.

Note the correction to the user's framing, because it decides scope: `@cpath:` is
**C-lane and IS the identity question**. "C is hardly relevant" is right about headers
*with guards* and not about path-form C units (`uses './x.c'`), which got `@cpath:`
precisely because unit-NAME keying collided. So C is not excluded from B — one of its two
mechanisms is absorbed by it.

### C — the preprocessor guards are NOT this concept, recorded so it stays settled

[[bug-c-header-with-a-body-compiles-twice-across-the-macro-reset]] and
[[bug-c-string-h-compiles-stdlib-c-twice]] are include-guard **visibility lost across a
macro-table reset**. The guard is present and correct in the source; pxx drops the macro
that implements it. That is a preprocessor-state-lifetime bug, not unit identity wearing
a similar symptom. They stay in their lane, fixed on their own terms.

**Recorded once, deliberately, per option C's purpose:** the next person who notices that
"header compiles twice" and "module compiles twice" look alike should read this section
and stop. The symptom is shared; the root is not. This was checked, not assumed, both at
filing and again here.

### MEASURED 2026-08-19 — B is much cheaper than this ticket prices it

The ticket's cost line ("it touches `parser.inc`'s load path — the thing every lane's
gate depends on") reads as greenfield work. It is not. **The mechanism already exists and
is already used for exactly this dedupe, on one arm only:**

| site | what |
| --- | --- |
| `compiler/defs.inc:2288` | `CompiledUnitFile : array[0..255] of Integer;` |
| `compiler/parser.inc:33942` | `CompiledUnitFile[...] := -1;  { filled in once resolved }` |
| `compiler/parser.inc:34590` | `if CompiledUnitFile[i] = pyFileIdx then pyDupIdx := i;` — **the .py arm** |
| `compiler/parser.inc:34616` | `CompiledUnitFile[savedCUC] := pyFileIdx;` |

So B is **promoting a built mechanism from a special case to the general rule**, not
inventing one. That is the shape `devdocs/dev/root-cause-over-microfix.md` prefers — it
deletes cases rather than adding a key space per surprise, which is exactly how `@cpath:`
came to exist.

**Hazard to carry into the work — the sentinel collides.** `CompiledUnitFile` is `-1` for
every entry not yet resolved to a file, and `-1 = -1`, so a generalised comparison makes
every unresolved unit identical to every other. The dedupe must skip `-1` explicitly.
This will pass every existing test and surface later as an ambient unit deduping against
a builtin.

### CORRECTION — the live bug is ALREADY FIXED, and option A is what fixed it

Checked before re-filing, and it changes what B means here.
[[bug-a-a-python-module-s-identity-is-its-name-not-its-file]] is in `done/`,
**resolved 2026-08-17, commit `030ce07ea`** — by adding `CompiledUnitFile[]` beside the
name key for the `.py` arm. That IS option A, taken before this decision was reached.

So the mechanism found above did not merely happen to exist: **option A built it**, which
is precisely why it serves one arm and no others. Nothing is blocked and nothing needs
reworking.

B is therefore not "fix the live bug properly" — it is **generalise what option A already
built**: populate `CompiledUnitFile` for every load that resolves to a file, consult it in
the already-compiled scan beside `guardIdx`, and retire `@cpath:` into it. Filed as its
own Track A ticket, since the bug that prompted the question is closed.

### Lane and sequencing

Carried into the new ticket. `parser.inc` is shared A/P ground, so this is a **sole-A job** — it must not be edited
concurrently with Track P. Gate is A's: `make compiler/pascal26` + repro +
`tools/gate.sh quick`. Land the general rule and the `-1` guard in ONE commit; a
half-applied change to the load path is the CRITICAL case `progress.sh check` fails on.

## Log
- 2026-08-19 — decided by user (B + C), moved to `decided/`.

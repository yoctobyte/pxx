---
slug: bug-a-audit-token-text-compared-against-a-keyword-the-lexer-never-leaves-as-text
title: "Audit: GetTokenStr compared against a keyword the lexer turns into its own token — a guard that can never be true"
track: R
type: bug
prio: 55
status: done
found: 2026-08-29
found-by: frank-rust (confirmed instance), swept by frank-coordinator
owner: frank-rust
---

# A guard that has never once been true, in three frontends' worth of candidates

## The confirmed instance

`impl Trait for Type` **had never been recognised by the Rust frontend. Not
"was broken" — had never once run.** Both the signature prescan and the body
parser detected the form with:

```pascal
(Tokens[j+1].Kind = tkIdent) and (GetTokenStr(j+1) = 'for')
```

The lexer classifies `for` as **`tkFor`**, whose name slice is empty. So the test
compared `''` against `'for'`, could never be true, and every `impl Area for Sq`
ever written was read as `impl <Area>` and died with `impl for unknown type Area`.
**The `RImpls` table it fills had been empty for the frontend's entire life.**

Fixed in rung 15 (`d9c15a5af`). This ticket is the *sweep* for its siblings.

## Why it is its own failure class

frank-rust's framing, and it is right that this is not face 36:

> Not a plausible wrong value, but **plausible-looking code that never executes.**
> It reads correctly, it is commented correctly, it sits in the right place, and
> no test could have caught it because the feature it implements was never
> available to test.

**A guard that has never once been true is invisible to every technique except
changing it.** Coverage cannot see it — the line is *reached*, the condition is
simply always false. Review cannot see it, because the code is correct-looking and
the bug is in the lexer's contract, one file away. It was found by trying to
**extend** the feature, which is the only thing that would have.

## The candidates — 17 sites, three frontends, NOT yet verified

Swept 2026-08-29 with a grep for `GetTokenStr(...) = '<keyword>'`. **Being on this
list is not a defect** — it is only a defect where that frontend's lexer emits a
dedicated token for that word. Each arm must be checked against **its own
lexer**, because the frontends have different keyword sets and this is exactly
the kind of list that gets read as a verdict:

| file | words compared | lane |
| --- | --- | --- |
| `rparser.inc` (11) | `mod`, `use`, `type`, `pub`, `enum`, `trait`, `impl`, `for`, `self`, `const` | **R** |
| `pyparser.inc` (4) | `as`, `self` ×3 | **N** |
| `zparser.inc` (2) | `struct` ×2 | **Z** |

**`self` in `pyparser.inc` is very probably CORRECT** — `self` is not a Python
keyword, it is an ordinary identifier, so `GetTokenStr` is the right way to test
it. That row is the reason this ticket is an audit and not a list of bugs.
`as` in Python *is* a keyword and is the one worth checking first.

## How to check an arm, cheaply

For each candidate, find whether the frontend's lexer has a dedicated token kind
for that word. If it does, the comparison is dead and the feature behind it has
never run — so also ask **what silently never happened**, which is the expensive
half. The `impl` case had an entire table (`RImpls`) that was always empty and no
test noticed, because you cannot write a test for a form the parser rejects.

## Filing

Each frontend fixes its own arm — `pyparser.inc` findings become **Track N**
tickets, `zparser.inc` findings **Track Z**. This ticket carries the R arm and the
sweep. Do not "fix" a row without confirming the lexer contract for that word;
a `GetTokenStr` test against a genuine identifier is correct code.

---

# AUDIT RESULT — 2026-08-29, frank-rust

**17 candidates, 1 defect, 16 correct.** The one defect is the confirmed
instance above and was already fixed in rung 15 (`d9c15a5af`). **Nothing else on
the list is a bug**, and the sweep was widened past the list without finding one.

Recording this as a RESULT so nobody re-runs it: the list was a good list, and
the answer is that the other sixteen rows are correct code.

## The finding is not the count — it is that the lexers disagree about this

Whether a text-vs-keyword comparison is dead depends on ONE line in each
frontend's lexer: which token kinds get their source text copied into
`TokChars`. Same-looking parser code, opposite verdicts.

| lexer | stores token text for | a text-vs-KEYWORD compare is |
| --- | --- | --- |
| `lexer.inc` (Pascal) | **every word token** — `CurTok.SVal := s` runs unconditionally after `Keyword(s)` | **SAFE** |
| `rlexer.inc` | `tkIdent`, `tkString`, `tkLifetime`, `tkInteger` | **DEAD** |
| `pylexer.inc` | `tkIdent`, `tkString`, wide `tkInteger` | **DEAD** |
| `zlexer.inc` | `tkIdent`, `tkString` | **DEAD** |
| `clexer.inc` | `tkIdent`, `tkString` | **DEAD** |

Pascal is the outlier, and it is the outlier in the SAFE direction — which is
also why the pattern reads as idiomatic to anyone who learned it there. Four
Pascal sites turned up when the sweep was widened (`Byte(x)`, `LongWord(x)`,
`Byte(p^) := v`, `Integer(x)` — all comparing `CurTok.SVal` against words the
Pascal lexer turns into `tkInteger_T` / `tkLongWord_T`), and **all four are
live**, precisely because of row one. Verified by running them, not by reading:

```
byte 65      { Byte(321) TRUNCATED -- the CaseEqual branch ran }
lw 321
lv 200       { Byte(p^) := 200, cast-as-lvalue }
int 321
```

## Per-row verdicts

- **`rparser.inc` `for` → `tkFor` — THE DEFECT.** Fixed rung 15. The nine other
  R words (`mod`, `use`, `type`, `pub`, `enum`, `trait`, `impl`, `self`,
  `const`) are **not** in `RKeyword`'s table, so all nine are correct. R's
  keyword set is only 14 words: fn if let mut for else true loop while break
  false return struct continue.
- **`pyparser.inc` `as` — CORRECT.** `as` is NOT in `PyKeyword`'s table; it
  stays `tkIdent`. The site even says so in its own comment. Verified by
  running `except ValueError as err:` → `caught boom`. This was the row flagged
  as "worth checking first"; it is fine.
- **`pyparser.inc` `self` ×3 — CORRECT**, as predicted: an ordinary Python
  identifier, not a keyword.
- **`zparser.inc` `struct` ×2 — CORRECT.** `struct` is not in `ZKeyword`'s
  table (Zig's 14 words are: fn if or and var for else true while break false
  const return continue). Verified: `test/test_zig_structs.zig` compiles and
  runs.
- **No Track N or Track Z ticket is needed.** Their arms are clean.

## The sweep was widened, and that is the part worth keeping

The original grep covered `GetTokenStr(..) = '<word>'` in three frontends. I
re-ran it over **all eleven frontends** (R, N, Z, C, Pascal, Ada, BASIC, e, f,
g, l), across `GetTokenStr(..)`, `CurTok.SVal` and `Tokens[..].SVal`, and
including the `CaseEqual(text, 'word')` spelling the first pass could not see —
each parser checked against **its own** lexer's table:

**561 text-vs-literal comparisons scanned. One dead guard, already fixed.**

So the pattern is rare and the codebase is in good shape on it. The reason to
have measured is that the one instance cost the Rust frontend its entire trait
system for its whole life, and no amount of review or coverage would have
surfaced it.

## What silently never happened — the expensive half, answered

`RImpls` had been empty forever, so anything reading it was also dead. Checked:
it is read only by the generic-bounds machinery, which had no other way to be
satisfied, so no *third* behaviour was silently wrong — the damage stops at
"`impl Trait for Type` did not compile". Also checked the inverse for Rust:
every one of `RKeyword`'s 14 tokens IS matched somewhere in `rparser.inc`, so
there is no keyword the lexer emits that the parser can never consume.

## Follow-up filed

[[feature-t-lint-token-text-compared-against-a-keyword]] (Track T) — the scan
is ~30 lines and mechanical: for each frontend, read its lexer's keyword table
and its text-storage rule, then flag any parser comparison of token text
against a keyworded word. It found this class once in 561 sites; a lint makes
that once-forever instead of once-per-audit. Not built here because
`tools/**` is Track T's lane.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

---
slug: bug-a-audit-token-text-compared-against-a-keyword-the-lexer-never-leaves-as-text
title: "Audit: GetTokenStr compared against a keyword the lexer turns into its own token — a guard that can never be true"
track: R
type: bug
prio: 55
status: backlog
found: 2026-08-29
found-by: frank-rust (confirmed instance), swept by frank-coordinator
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

---
track: T
prio: 40
type: bug
blocked-by: []
summary: "177 slug-shaped ticket citations in `compiler/**` and `lib/**` comments resolve to NO file under devdocs/progress/ (measured 2026-09-11 at 041f279e1; 2058 of 2400 citations DO resolve, which is the positive control). The sharp subset is frankB's: a comment that cites a slug AND justifies a live refusal on the filing existing -- pyparser.inc:23973, bug-a-nilpy-enumerate-over-str-inline-param-leak, no ticket. A CHECKER IS THE RIGHT FIX AND MUST CARRY A BASELINE, because 177 legacy rows make a bare checker a gate that cannot pass. The matcher needs four specific corrections or it reds falsely -- my own first answer was 345."
status: backlog
---

# 177 slug citations in `compiler/**` and `lib/**` resolve to no ticket

**Found by frankB 2026-09-11** (one instance, chased from a comment whose premise
was false), **population measured here the same evening.**

## The sharp subset, and why it is worse than a stale fact

`compiler/pyparser.inc:23973` cites
`bug-a-nilpy-enumerate-over-str-inline-param-leak` and nothing in
`devdocs/progress/**` covers it. It is guarding a LIVE refusal — `enumerate()`
over a `str` is rejected outright — and the comment's justification is that the
leak is filed. It is not.

**A comment asserting that PAPERWORK EXISTS is checkable and was false**, and a
cited slug is worse than an unsourced claim: a slug *looks* checkable, so a reader
stops at the sight of it rather than at the sentence. The citation is what buys the
trust. Related: a hazard block succeeds by stopping you, so obeying one generates
no signal.

## The population

Measured at `041f279e1`, `compiler/**` and `lib/**`, slug-shaped citations
(`bug-`, `feature-`, `task-`, `decide-`, `compat-`, `refactor-`, `umbrella-`):

| | |
| --- | ---: |
| distinct citations | 2400 |
| **resolve to a file under `devdocs/progress/`** | **2058** |
| resolve only as a PREFIX (renamed or extended slug) | 21 |
| **resolve to nothing** | **177** |

2058 resolving is the positive control: the matcher finds real tickets, so the 177
is not an instrument that matches nothing.

## DO NOT BUILD THE CHECKER WITHOUT THESE FOUR CORRECTIONS

My first answer was **345**, and every step down was an instrument error, not a
fix to the tree. A checker shipped with any of these unfixed reds on valid rows:

| correction | count |
| --- | ---: |
| first answer | 345 |
| citations **wrapped across comment lines** — the slug continues on the next line, so a line-scoped grep captures a truncated prefix ending in `-` | 199 |
| slugs that resolve as a **prefix** of a longer real filename (renamed or extended since the comment) | 178 |
| **hyphen is not a word boundary** — `\bcompat-philosophy` matches inside `frontend-compat-philosophy.md`, a devdocs file that is not a ticket | **177** |

Two controls, both required and both cheap: `compat-philosophy` must NOT appear
(known false positive) and `bug-a-nilpy-enumerate-over-str-inline-param-leak` MUST
appear (known true positive). A matcher passing only the first is too aggressive.

## Design

**The checker needs a baseline file**, the way `tools/ast_slot_overloads.py`
carries `test/ast_slot_writes.expected`: snapshot the 177 and red only on a NEW
unresolved citation. A bare checker is a gate that cannot pass, which this repo
already names as not a gate at all.

The rule to enforce is frankB's: **cite a slug or do not claim the filing, and the
slug must resolve to a file.** The 177 existing rows are a separate cleanup and
should not block the checker — most are probably citations to tickets that were
deleted or renamed rather than fictional, and **establishing which is unbounded
per row**, which is exactly why frankB declined to sweep them and filed instead.

## Not measured

Whether any of the 177 guards a live behaviour the way `:23973` does. That is the
question that would raise the prio, and it is a per-row read. frankB's one
instance found it on the first row they looked at, which is not a sample.

---
slug: feature-t-lint-token-text-compared-against-a-keyword
title: "Lint: a parser comparing token TEXT against a word its own lexer keywords — a guard that can never be true"
track: T
type: feature
prio: 35
status: rejected
found: 2026-08-29
found-by: frank-rust
---

# Make the never-true guard a lint instead of an audit

Filed out of [[bug-a-audit-token-text-compared-against-a-keyword-the-lexer-never-leaves-as-text]],
which measured the class once: **561 text-vs-literal comparisons across eleven
frontends, one dead guard.** That one cost the Rust frontend `impl Trait for
Type` for its entire life — `RImpls` was empty from the day it was written, and
neither review nor coverage could see it (the line IS reached; the condition is
simply always false, and the bug lives in the lexer's contract one file away).

## The check

For each frontend, two facts come out of its lexer:

1. **the keyword table** — which words become a dedicated `tkX` instead of `tkIdent`;
2. **the text-storage rule** — which token kinds get their source text copied
   into `TokChars` (one `if` in that lexer's `*LexAll`).

Then flag any parser comparison of a token's TEXT (`GetTokenStr(..)`,
`CurTok.SVal`, `Tokens[..].SVal`, including inside `CaseEqual`) against a word
that (1) keywords and (2) does not store text.

Both halves are required, and that is the whole subtlety: **the Pascal lexer
sets `CurTok.SVal` unconditionally, so the same code is correct there** — four
Pascal sites (`Byte(x)`, `LongWord(x)`, `Byte(p^) := v`, `Integer(x)`) look
exactly like the Rust bug and are live. A lint that skips step 2 turns those
into false positives and gets scrolled past, which is worse than no lint.

## Why Track T and not the frontends

It is tooling over every frontend at once, `tools/**` is T's lane, and the
per-lane fix is one line wherever it fires. The audit's contract table (in that
ticket) is the data the lint needs and is already written down.

## Not urgent

prio 35 on a measured base rate of 1-in-561. This is a "never again" lint, not
a backlog of hits waiting to be found.

## Rejected 2026-09-02 — the Track T tooling backlog was cut as a pile

Owner decision, not a judgement on this ticket individually. 73 of the 74 open
`track: T` tickets were filed between 2026-08-31 and 2026-09-02, 58 on one day.
The pile was too large to work through, and a ticket nobody will fix does not sit
neutrally: it stays in the ranker forever at zero value, which is the same
argument CLAUDE.md already makes for `rejected/` over a low prio.

Four were kept, on a purely structural test — an active umbrella, or a hard
`blocked-by:` edge from live non-T work: `umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**This is a reversible archive, not a deletion.** If one of these is refiled
later, it should be refiled with the evidence that makes it worth doing rather
than restored wholesale.

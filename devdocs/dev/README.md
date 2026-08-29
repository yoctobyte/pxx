# `devdocs/dev/` — three kinds of file in one directory

52 files, three categories, and **the directory does not encode which is which**.
That matters because they have opposite editing rules, and getting it wrong in
one direction falsifies history.

This page exists because an audit of the live references was dispatched as
*"audit `devdocs/dev/*.md`"*, and taken literally that rewrites ten session
records on the tenth file. The auditor spotted it and left them alone; the
next one might not.

## 1. LIVE REFERENCES — fix them when they are wrong

The default. Everything not named below. These describe how the project works
*now*, are read to decide what to do, and a stale one is a **bug**.

CLAUDE.md is the authority over all of them: *"If a live reference doc
(`devdocs/dev/*.md`) contradicts this section, that doc is the bug: fix the doc,
not the loop."* And CLAUDE.md itself is the owner's — flag a contradiction,
never edit it.

## 2. SESSION RECORDS — never edit, however wrong

A record of what one session actually ran, on the day it ran. **Several contain
figures and gate lines that are false today, and that is correct behaviour for a
record.** Rewriting one falsifies history and is explicitly forbidden by
CLAUDE.md's precedence rule, which also warns that some of them predate the
current per-fix loop and name the heavy pin-gate mode (`gate.sh full`) as if it were
the dev loop. **Never widen your gate on their authority.**

```
handover-2026-06-28-track-abc-cleanup.md   handover-2026-07-18-float-int-perf.md
handover-2026-07-03-optimization-arc.md    handover-2026-08-05-track-d.md
handover-2026-07-04-track-a.md             next-session-indexed-proc-call-prompt.md
handover-2026-07-18-evening-o3-arc.md      next-session-nilpy-bughunt-prompt.md
next-session-pal-prompt.md                 next-session-promo-surface-prompt.md
```

Enumerate them with: `ls devdocs/dev/ | grep -E '^(handover-|next-session-)'`

## 3. CARRIED PROMPTS — a third category, and the reason a filename pattern is not enough

A prompt written for a future session to pick up. Not a historical record, so
correcting one falsifies nothing; not a live reference either, so nothing else
depends on it being right. Fix a stale fact in one freely; do not treat it as
authority.

- `eliah-m4-m5-prompt.md` — Track B / Eliah IDE. Names a `cwd` that may no
  longer exist; read the paths sceptically.

**`*-prompt.md` maps to all three categories, which is exactly why this page
lists files rather than a pattern.** `claude-B-prompt.md` is a **live
reference** — CLAUDE.md:567 cites it in the Platonic-code rule — while four
`next-session-*-prompt.md` files are records and `eliah-m4-m5-prompt.md` is a
carried prompt. A reader inferring the rule from the suffix gets it wrong in
both directions.

`session-roster.md` is also live, and is the one file here that is *supposed* to
be rewritten continuously: it is the coordinator's durable state.

## Adding a file

New session record → prefix `handover-` or `next-session-` **and add it to the
list above**. The list is the mechanism; the prefixes are only a hint, and a
hint that has already been shown to mislead.

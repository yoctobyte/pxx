---
track: A
prio: 35
type: bug
blocked-by: []
summary: "`--strict-fpc` is accepted, documented at defs.inc:2189-2191, and demonstrably changes behaviour -- and does not appear in `--help`. 67 markdown files name flags `--help` does not advertise. The failure mode is not a missing line of text: an agent reasoning from `--help` concludes the flag DOES NOT EXIST and that whatever cites it named a fiction, which is a wrong conclusion reached by consulting the tool's own self-description."
status: backlog
---

# `--help` does not advertise flags the compiler accepts

**Found by frankD, 2026-08-30**, while measuring a dangling implementation link
in `decide-typeinfo-scalar-name-spelling`. It nearly took the trap, and the trap
is the reason this is a bug rather than a documentation chore.

## The measurement

`--strict-fpc` is **not in `--help`**. Reasoning from that, the obvious
conclusion is that the flag does not exist and the decision citing it named a
fiction. That conclusion is **wrong**, and three independent things say so:

- the compiler **accepts** it. Control, and this is the part that makes it
  evidence rather than an impression: `--nonsense-flag` gives `unknown option`,
  so the parser is not merely ignoring unrecognised input;
- it is **documented in the source** as an umbrella flag, `defs.inc:2189-2191`;
- it **demonstrably changes behaviour** — `Char(Variant(65))` gives `A` by
  default and `6` under it.

**67 markdown files name a flag `--help` does not advertise.** That count is the
scale of the gap, not the size of the fix; most of those files are presumably
right and `--help` is the thing that is behind.

## Why this is a bug and not a docs ticket

`docs/**` is Track D and prose is D's lane. **This is not that.** The help text
lives in `compiler/`, and the defect is that **the tool's own self-description
disagrees with the tool**. A reader who checks a claim against `--help` — which
is the correct instinct, and the cheapest check available — gets a confident
negative for a flag that works. That is the shape the method index keeps
recording under a different name: an instrument that reports something adjacent
to the truth costs more than an instrument that reports nothing, because the
answer it gives is actionable and wrong.

The direction matters. A flag missing from `--help` does not produce "I am not
sure"; it produces **"that flag does not exist"**, and the next move after that
conclusion is to go and correct whatever cited it. A ticket, a decision, or a
doc gets edited to remove a true reference on the authority of an incomplete
help text.

## Scope, and what NOT to do

**Do not fix this by adding `--strict-fpc` to `--help`.** That repairs the one
instance and retires the only detector for the other 66 — the same move the
index has as "repairing the visible defect retires the only detector for the
invisible one". The measurement to take first is the **set**: which flags does
the argument parser accept that `--help` does not print? That is enumerable from
the parser rather than from a grep of the docs, and enumerating it from the
artefact rather than from the citing source is the whole point.

Then decide, deliberately, which of the two properties is wanted:

1. `--help` prints every accepted flag (long, and some are experimental or
   internal — that is a real cost, not an obvious win);
2. `--help` prints the supported set, and every accepted-but-unlisted flag is
   marked in the source as deliberately unadvertised, so the *next* enumeration
   can tell "hidden on purpose" from "forgotten".

Option 2 is the recommendation: the defect is that the two sets differ **with
nothing recording the difference**, and an unadvertised flag is legitimate. What
is not legitimate is that today there is no way to tell which is which.

If a check is cheap, the strongest form is a test asserting the parser's
accepted set equals the advertised set plus an explicit hidden list — that turns
a documentation property into a gated one and it cannot rot silently.

## Provenance

`decide-typeinfo-scalar-name-spelling` [U p20] cited
`feature-a-typeinfo-integer-name-under-strict-fpc` as its implementation for
nine days; the link resolved to nothing, and frankD filed the ticket under the
exact slug the decision names after confirming the arm really is missing
(`TypeInfo` of a plain `Integer` reports `Integer` under default, `--mimic-fpc`,
`--strict-case` **and** `--strict-fpc`; FPC 3.2.2 says `LongInt`). That is a
separate, low-prio compat item. **This ticket is only about the help text.**

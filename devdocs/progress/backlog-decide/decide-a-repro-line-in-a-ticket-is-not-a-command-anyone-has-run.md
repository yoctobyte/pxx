---
prio: 45
track: U
---

# decide: should the handbook say that a repro line in a ticket is not a command anyone has run?

**A proposal for the owner, not an edit.** CLAUDE.md is his; this ticket exists
so the claim can be judged rather than quietly landed. Two other CLAUDE.md
proposals are already queued (franka-29 and frankb-78, canary-rc-vs-stage and
encoding-rules-as-checks); if he takes any of the three, they should be weighed
together, because all three are the same argument in different clothes.

## The fork

The handbook has a large section on *"the name is not the thing"* and on
instruments that lie by being correct about something else. It does not name the
case where the artefact is a **command**, and the command has never been
executed by the person who wrote it down.

Should it? Or is this covered well enough by the existing rule and not worth
another paragraph in a file every session pays for at startup?

## What happened, 2026-09-03

The coordinator handed frankh-15 a verification command taken from an auto-filed
ticket's own `## Repro` line. It was refused by `.claude/hooks/no-full-suite.sh`.
The line was correct as a description and had never been run by anyone —
twatch generates it, and the hook that would decline it is a different mechanism
that nobody had crossed with it.

**Scale, counted by folder rather than by a glob across all of them:** 6 of 6
tickets in `backlog/` — the folder twatch files into, i.e. **100% of the
auto-filed regression population** — carried a repro command the repo refused.
0 of 142 in `backlog-core`, 0 in `backlog-tools`, `working`, `unfinished`,
`blocked`, `urgent`.

The hook is fixed (`448b21c11`), so the specific instance is gone. The question
is whether the CLASS is worth a rule.

## The case FOR

It is the same animal as a comment that has drifted from its code, which the
handbook already treats as a first-class hazard — but a comment at least looks
like prose you must judge, while **a command looks executable, and being
copy-pasteable is exactly what makes it trusted unread.** Every ticket template
in this repo emits one. It is generated text wearing the costume of a receipt.

## The case AGAINST

CLAUDE.md was cut from 72KB to rules in August because every session paid the
history at startup, and the bar for a new paragraph should be high. This may be
one instance, now fixed at the source; a rule earns its place by preventing a
recurrence, and the hook fix already prevents this one. There is also a cheaper
form: make the ticket generator emit a line it has verified, or say in the
template that it has not.

## Recommendation

**Not a CLAUDE.md paragraph — a one-line change to the template.** Have twatch
label the repro as generated-and-unrun, or verify it before writing it. That
puts the caveat where the artefact is, costs no startup tokens, and cannot go
stale in the way a rule about a mechanism can. Escalate to prose only if a
second, differently-shaped instance shows up. Owner's call.

## Provenance

Raised by frankh-15 after fixing the hook, and filed by the coordinator rather
than acted on, because a peer asking for a handbook change is not authority to
make one. Recorded here so the owner sees the request and its counter-argument
in the same place.

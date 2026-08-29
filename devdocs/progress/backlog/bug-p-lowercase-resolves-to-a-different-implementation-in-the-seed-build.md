---
track: P
prio: 45
type: bug
blocked-by: []
summary: "pasparser_expr.inc:1927 uses LowerCase before this codebase declares it at pasparser_proc.inc:2384. FPC resolves it to its OWN system-unit LowerCase; pxx resolves it to ours. Both builds succeed, so no gate fires — but the FPC-seeded compiler and the self-hosted compiler are running DIFFERENT implementations of LowerCase at this call site. Not a build failure: a silent behavioural fork between two builds of the same source."
status: backlog
owner: ""
---

# `LowerCase` resolves to a different implementation in the seed build than in the self-hosted build

Reported by `tools/forwardlint.py`, which classifies it as a **note** rather
than a FAIL — correctly, because it builds either way.

```
note compiler/pasparser_expr.inc:1927: uses LowerCase before this codebase
     declares it at compiler/pasparser_proc.inc:2384 — FPC resolves it to its
     OWN system-unit routine, so the seed build and the self-hosted build run
     different implementations here. Builds either way.
```

## Why this is a bug and not a curiosity

pxx resolves names across the whole unit; FPC resolves in source order. At
`:1927` FPC has not yet seen our `LowerCase`, so it binds the **system unit's**.
pxx binds **ours**. Same source, two builds, two different routines called.

That is fine *if and only if* the two implementations agree on every input this
call site can produce. Nobody has checked that they do, and the divergence is
invisible: both builds succeed, both self-host, and no gate compares them. The
failure mode is a compiler that behaves differently depending on **how it was
built**, which is the hardest class of bug this repo can have — it breaks the
assumption every bisect and every fixedpoint claim rests on.

Note the specific hazard for a Pascal parser: `LowerCase` on non-ASCII bytes is
exactly where a system-unit implementation and a hand-rolled one are most likely
to differ (locale handling, bytes ≥ 128). Identifier case-folding is on the path
for every source file compiled.

## Fix

Add a `forward;` for our `LowerCase` above `:1927`, or move the declaration —
whichever the lane prefers. That makes both builds bind the same routine and
removes the fork. **Before doing that**, diff the two implementations on the byte
range this call site can see: if they already agree, the fix is a one-liner and
the ticket closes; if they do **not** agree, the seed-built compiler has been
behaving differently from the self-hosted one and that is a much larger finding
than this ticket.

Do not "fix" it by deleting our `LowerCase` and relying on the system unit
without checking the same question — that changes which implementation the
self-hosted build uses, silently, in the other direction.

## Provenance

Surfaced 2026-08-29 while wiring `tools/forwardlint.py` into `gate.sh`, on the
same run that caught the p80 `RExprRecId` seed break. The lint had been reporting
both for a day; nothing invoked it.

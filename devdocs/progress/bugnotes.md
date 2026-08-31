# bugnotes — findings that do not need a ticket

**One paragraph each. Newest at the bottom. No frontmatter, no slug, nothing to
resolve.**

A finding lands here when **no umbrella needs it** (see CLAUDE.md, *Umbrellas —
the goal is the ranking*). That is not a judgement that it is wrong or
uninteresting: it is accurate, it is recorded, and it is simply **unranked**
until some real program reaches for it.

Owner, 2026-08-31, on why this file exists: the backlog reached 400+ open
tickets — 467 open of 5035 ever filed — *"half fair and accurate, but not related to primary
development target."* Perf numbers, a float's last decimal, an FPC or gcc
divergence, an observable no compiling program can reach. **The ticket system
became its own flaw** — so the default moved: a note is the default, a ticket is
the exception.

## What still earns a ticket

Anything that needs **coordination, ranking or memory** — the same test the
*Ticket economy* section already applies. In practice:

- real code compiles wrong, crashes, hangs, or produces a wrong value;
- it blocks a named umbrella (say so, and wire the `blocked-by` edge);
- somebody else must act on it, or a diagnosis would otherwise be re-derived.

Everything else: one paragraph here. **Say what you measured, on which sha, and
what you would look at next.** Do not write a diagnosis you have not verified —
an unverified paragraph here is worse than nothing, because the next reader
cannot tell it from a measured one.

## Triage

In bulk, later, when an umbrella reaches for something. A note that turns out to
block a goal gets promoted to a ticket and wired; the rest stay here. **Nothing
here is deleted** — it is cheaper to keep a paragraph than to re-discover it.

---

<!-- Append below. Format: date | agent | one paragraph. -->

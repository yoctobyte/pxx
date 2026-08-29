---
slug: bug-a-lowercase-resolves-to-two-different-routines-depending-on-the-seed
title: LowerCase resolves to two different routines depending on which compiler builds the compiler
track: A
type: bug
prio: 35
status: backlog
found: 2026-08-28
found-by: frankwasm (via tools/forwardlint.py), verified by frank-coordinator
---

## The fact

`compiler/pasparser_expr.inc:1924` calls `LowerCase`:

```pascal
PyStoredName(LowerCase(Strs[CurrentUnitIdx].Text) + '.py');
```

This codebase declares `LowerCase` at `compiler/pasparser_proc.inc:2384` — **460 lines and
one file later** — and forward-declares it **nowhere** (`grep -rn "LowerCase.*forward"
compiler/` is empty; verified independently by the coordinator).

So the call resolves differently depending on which compiler is building:

| build | `LowerCase` at line 1924 resolves to |
| --- | --- |
| **FPC seed** | FPC's **own** system/sysutils routine |
| **self-hosted pxx** | this codebase's routine at `pasparser_proc.inc:2384` |

It compiles both ways, which is why `forwardlint` reports it as a **note**, not a failure.

## They agree today — and that is the whole point

Do not fix this expecting a wrong answer. The local implementation is ASCII-only:

```pascal
if res[i] in ['A'..'Z'] then res[i] := Chr(Ord(res[i]) + 32);
```

and FPC's `AnsiString` `LowerCase` is ASCII-only too. **The two implementations agree on
every input this call site can currently receive** (a unit name). There is no observable
misbehaviour to reproduce, and a ticket that promised one would be wrong.

The defect is that **the agreement is a coincidence that nothing enforces.** It survives
only while both routines stay ASCII-only and the input stays a unit name. Either can change
without anyone touching this line, and nothing anywhere would notice.

## Why no gate can catch this class — including the one we trust most

This is the part worth generalising beyond the ticket.

**The self-host fixedpoint cannot see this, and never will.** It proves that pxx-built-pxx
reproduces itself byte for byte. It does **not** compare the FPC-seeded build's *behaviour*
against the self-hosted build's. A name that binds to a different routine under the two
compilers is invisible to it **by construction**, not by oversight — both builds are
internally consistent, and the fixedpoint only ever asks about internal consistency.

Same shape as the scope note already in `CLAUDE.md` about the fixedpoint proving self-compilation
at **one** optimisation level. The gate is strong and narrow, and its narrowness is
load-bearing in both cases.

`tools/forwardlint.py` is currently the only thing in the repo that can see this class at all,
which is a second argument for the pending decision in
`decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop`.

## The fix, and the reason it is worth doing at prio 35 rather than 10

Add `function LowerCase(const s: AnsiString): AnsiString; forward;` to the appropriate
forward block, or move the definition ahead of first use. Trivial.

The value is not the divergence — it is that **`forwardlint` prints exactly one note on a
clean tree, and this is it.** If that lint joins the mandatory loop while this note persists,
every agent learns on day one that its output contains something you are supposed to ignore.
This repo has already recorded the rule (`a check that cries wolf is worse than no check`);
a permanent note on a green tree is the slow version of the same failure.

**Fix this before adopting the lint, not after.** Then `forwardlint` is silent when correct,
which is the only state in which anyone reads its output.

## Do NOT

Do not allowlist the note. Suppressing the one finding a new check produces, in order to
adopt the check, discards the check's only demonstrated result.

---

## MERGED 2026-08-29 — a duplicate of this ticket, and what it adds

`bug-p-lowercase-resolves-to-a-different-implementation-in-the-seed-build` was
filed today by the coordinator from a fresh `forwardlint` run, **not knowing this
ticket existed** — although this ticket's own frontmatter records
`found-by: frankwasm (via tools/forwardlint.py), verified by frank-coordinator`
on **2026-08-28**. A previous session of the same role had already verified it.
The duplicate is in `rejected/` as a tombstone, not deleted, so citations resolve.

**What the duplicate adds, kept because it is not in this ticket:**

- **Current line numbers.** `pasparser_expr.inc:1927` uses `LowerCase`;
  declaration at `pasparser_proc.inc:2384`.
- **The specific hazard for a Pascal parser.** `LowerCase` on non-ASCII bytes is
  exactly where a system-unit implementation and a hand-rolled one are most
  likely to diverge — locale handling, bytes ≥ 128 — and identifier case-folding
  is on the path for **every source file compiled**.
- **Fix ordering.** Before adding the `forward;`, **diff the two implementations
  over the byte range this call site can see.** If they already agree, it is a
  one-liner and this closes. If they do **not** agree, the seed-built compiler
  has been behaving differently from the self-hosted one, and that is a much
  larger finding than this ticket.
- **The anti-fix.** Do *not* resolve it by deleting our `LowerCase` and relying
  on the system unit without asking the same question — that changes which
  implementation the **self-hosted** build uses, silently, in the other
  direction.

**Track question, left open rather than silently changed:** this ticket says `A`,
the duplicate said `P`. Both call sites are in P's carved-out `pasparser_*.inc`,
which argues P; the shared `LowerCase` and the seed-build property argue A.
Whoever takes it should set the letter deliberately. Prio here is 35; the
duplicate argued 45 on the grounds that a silent behavioural fork between two
builds of the same compiler is worse than a cosmetic divergence. **Not
re-prioritised by the duplicate's author** — that call belongs to whoever owns
the lane, and re-ranking someone else's ticket to match your own filing is how a
board loses its ordering.

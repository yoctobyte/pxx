---
slug: bug-a-lowercase-resolves-to-two-different-routines-depending-on-the-seed
title: LowerCase resolves to two different routines depending on which compiler builds the compiler
track: A
type: bug
prio: 35
status: done
found: 2026-08-28
found-by: frankwasm (via tools/forwardlint.py), verified by frank-coordinator
owner: frank-optimize
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

---

## MEASURED 2026-08-29, host `seven` — the two implementations AGREE EXHAUSTIVELY

This ticket's fix-ordering condition — *"before adding the `forward;`, diff the
two implementations over the byte range this call site can see. If they already
agree, it is a one-liner and this closes"* — is now answered with a real
measurement rather than by reading both sources.

It could not be answered before on a watcher box: it needs FPC's actual routine,
and `fpc` was installed on `seven` only today. Reading FPC's source would have
been the re-derivation the ticket is careful to avoid; this runs it.

Method: an FPC program calling `sysutils.LowerCase` beside a byte-for-byte
transcription of `pasparser_proc.inc:2384`, comparing outputs.

| domain | inputs | differing |
| --- | --- | --- |
| every single byte | 256 | **0** |
| every ordered byte **pair** | 65 536 | **0** |
| `'Unit' + <byte> + 'Name.Sub'` (the call site's actual shape) | 256 | **0** |

The pair sweep is the one that matters and is why it is here: a single-byte
sweep cannot distinguish a per-character implementation from a sequence-aware
one, and *"locale handling, bytes ≥ 128"* — the hazard the merged duplicate
names — is exactly where a multi-byte-aware routine would diverge. It does not.
FPC 3.2.2's `AnsiString` `LowerCase` is per-character ASCII, identical to ours
over the whole domain.

**So the fix is the one-liner branch, and the larger finding the ticket held
open — that the seed-built compiler has been behaving differently from the
self-hosted one — is RULED OUT.** Not "no evidence of": measured absent over
every input of length ≤ 2.

**None of this weakens the ticket's actual argument, and it should not be read
as a reason to downgrade it.** The defect was never that the answers differ; it
is that *the agreement is a coincidence nothing enforces*, and that
`forwardlint` prints exactly one note on a clean tree and this is it. Both still
hold. What changes is only the risk of the fix: it is now demonstrably a
`forward;` with no behaviour change to chase, so **nothing blocks it ahead of
adopting the lint** — which is the ordering the ticket asks for.

Measured by the Track T agent on `seven` (provenance: my box's gate produced the
note). The `forward;` itself is `compiler/**`, a file-lane this session does not
hold, so it stays unwritten here — as does the open A-vs-P track question, which
the ticket rightly says belongs to whoever takes it.

---

## FIXED 2026-08-29 — `frontend_forwards.inc`, and the seed build was ALREADY identical

`function LowerCase(const s: AnsiString): AnsiString; forward;` added to
`compiler/frontend_forwards.inc`, which enters the include stream at
`compiler.pas:120` — ahead of `pasparser_expr.inc` (139), `pasparser_proc.inc`
(142) and `cparser.inc` (168), so it covers every use, not just the one the lint
named. There are more than the ticket lists: `pasparser_expr.inc:1927`, `:2881`,
`:8383`, `:8386`, `:8389` and `cparser.inc:337`, `:395`, `:510`. `forwardlint`
reports only the earliest.

**Track: P.** `pasparser_*.inc` was carved out of A on 2026-08-20 and P owns it;
the fix itself lands in a shared frontend forwards file, and the gate is the
ordinary loop, which proves the fixedpoint anyway. Settled deliberately rather
than left open, as the ticket asked.

### The ticket's precondition, answered twice by two different methods

Track T's sweep on `seven` compared the two *implementations* over their input
domain: 0 differing over 256 single bytes, 65536 ordered pairs, and 256
call-site-shaped strings.

This session added an independent **end-to-end** check, because the two methods
can fail differently: an input-domain sweep proves the routines agree on inputs
someone chose to try, while a binary comparison proves the whole seed-built
compiler is unchanged whichever routine it bound.

```
  seed-built compiler WITHOUT the forward:  9396c6dbb646f90d
  seed-built compiler WITH the forward:     9396c6dbb646f90d
  self-hosted compiler:                     9396c6dbb646f90d
```

All three byte-identical. `make bootstrap` green both ways (FPC -> pxx -> pxx,
`cmp` passing).

**So the seed build was ALREADY producing the identical compiler, and this fix
did not cause that convergence — it recorded it.** Worth stating plainly,
because "the seed and self-hosted builds now agree" is the tempting sentence and
it would be false: they agreed before. What changed is that the agreement is now
*stated* rather than *coincidental*, which is the defect this ticket actually
described.

This also closes the larger finding the ticket held open — *the seed-built
compiler has been behaving differently from the self-hosted one* — from a second
direction. Track T ruled it out over the input domain; this rules it out over
the artefact.

### Why it was worth doing with no behaviour change

`forwardlint` is now **silent on a clean tree** — that was the whole argument at
prio 35, and it is the state the ticket asked for before the lint joins the
mandatory loop. A canary with one permanent known exception is a canary people
learn to scroll past.

### Not done, deliberately

The `Do NOT` in this ticket is observed: nothing was allowlisted, and our
`LowerCase` was not deleted in favour of the system unit.

One observation for someone else, filed nowhere because it is not this ticket's
business: `LowerCase` is now shared between the Pascal parser and the **C**
parser (`cparser.inc`). `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`
says to share the AST and the IR and to duplicate parser support functions per
language. A case-folding helper shared across two frontends is exactly the shape
that document argues against. It is not a defect today and the forward does not
make it worse; it is the kind of thing that is invisible until someone changes
one language's needs.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

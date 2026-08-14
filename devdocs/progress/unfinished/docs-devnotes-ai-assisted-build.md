---
prio: 50
---

# Developer notes: how this was actually built (AI-assisted, and honest about it)

- **Type:** docs
- **Track:** D (docs) — the user writes the substance; the agent's job is scaffolding + accuracy
- **Status:** unfinished — agent half (scaffold + fact-check) done 2026-08-14;
  parked awaiting the user's substance. See the Log.
- **Owner:** claude-D
- **Related:** [[feature-promo-launch-plan]]

## Position: LEAD with it, never hide it
The user has never intended to conceal that this project is AI-assisted — **the opposite**.
Documenting how it went is a stated **sub-goal of the project itself** (see also the ticket
board: the record IS a deliverable). The commit trailers say it anyway; concealment was never
on the table and would poison the whole thing if it surfaced after a launch.

## The claim that MUST NOT be flattened
> *"This was not 'let's prompt and see what AI can do'."*

There is **serious human time investment** here — architecture, direction, review, judgment
calls, and a lot of hours. The user designed the compiler's architecture (lexer, parser,
symtab, x86-64 codegen, IR, ELF writer) and reads the output rather than rubber-stamping it.

This nuance is the **load-bearing** part of the story and the first thing a careless summary
destroys. Both cheap framings are false:
- ❌ *"AI wrote a compiler"* — flattering, false, and instantly demolished.
- ❌ *"AI is useless for real systems work"* — the artifact refutes it.
- ✅ The true, interesting claim: **a human architect + agents, over a long haul, with a
  verifiable gate, went far past what the human expected — and the evidence is public.**

## The intuition worth recording (user's own words, 2026-07-12)
> *"It obliterated my expectations. We went way further than this 'proof of concept'. Yes, it
> still took me a lot of time. It just exceeded even my own expectations, and still going."*

That is the honest headline: not "look how easy", but **"I aimed at a proof of concept and hit
a self-hosting multi-frontend compiler, and I have the receipts."** Write it that way.

## Why this project is unusually good evidence (and most such posts are not)
Nearly every "I built X with AI" account is reconstructed from memory afterwards and is
**unfalsifiable**. This one is not:
- **Self-host fixed point** — the compiler compiles its own source to a byte-identical binary.
  A verifiable, mechanical gate. (Claims discipline: this is *binary* identity of our own
  output; the gcc-oracle corpus claims are *behavioral* parity — see CLAUDE.md. Never blur.)
- **200+ pinned stable versions** — the whole trajectory, not a snapshot.
- **The ticket board** — with `Log` sections recording what was tried, what failed, what was
  abandoned, written *at decision time* rather than in hindsight.
- **tstate regression reports** tied to exact SHAs; a cross-target test matrix.
- **The commit log**, with agent co-authorship, never scrubbed.

Nobody else has this dataset. It is the moat of the *narrative*, and it is a byproduct of how
the project already runs.

## Scope
1. Promote the passing aside at `devdocs/developer/developer-notes.md:107` ("This is totally
   vibe-coded…") into a **stated goal with a method**, and decide what belongs in public
   `docs/**` vs internal devdocs.
2. **User writes the substance**: his notes on progress and his intuitions. Agent drafts
   structure, fact-checks every claim against the record, and refuses to overstate.
3. Candidate sections: what was expected vs what happened · where the agents were strong ·
   where they were bad (be specific — this is what makes it credible) · the human hours and
   what they went into · the workflow that made it work (tracks, tickets, gates, pins) · what
   we'd do differently.
4. **Include the failures.** A post that only reports triumph reads as marketing. The bug
   post-mortems (e.g. the string-literal decay *family*, the 32-bit heap corruption, longjmp
   rolling back resident registers) are the most convincing material we have, precisely because
   they show what the process actually costs.

## Log
- 2026-07-12 — opened. The AI-assisted angle is a *feature* of the story and is to be led with,
  not buried; the human-investment nuance is the part that must survive editing.
- 2026-08-14 — **agent half done; parked on the user.** Scaffold + verified fact
  sheet written to `devdocs/dev/how-this-was-built-draft.md` (draft, deliberately
  NOT in `docs/**` — the website publishes that verbatim, so placeholders would
  go live). It carries: every number measured from this checkout with the command
  to re-measure it; the three numbers that need a qualifier in the same sentence
  or they will be misread (46% of commits carry an agent trailer, not all; the
  track split covers 865 of 1774 done tickets, not all; 303 pins are checkpoints,
  not releases); the two-different-"byte-identical" claims-discipline landmine;
  and the seven-section structure with the user's sections left explicitly empty.
  Failure material for §5 located and counted rather than asserted — the
  string-literal family is 15 tickets in `done/`, plus the longjmp/resident-param
  bug and the wrong-root-cause incident that produced `PXXDBG`.
  **Four questions for the user are in Part 3 of the draft** (voice/length, does
  the fact sheet ship, how blunt §5 gets, what happens to the "totally
  vibe-coded" aside). Moved to `unfinished/`: what remains is substance only the
  user can write, and the landing spot is decided (`docs/how-this-was-built.md`,
  `order: 6`, next to Dive).

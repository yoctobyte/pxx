---
track: W
prio: 35
type: feature
blocked-by: []
summary: "`/blog/` returns 200 and says `Coming soon.` [[feature-promo-launch-plan]] already decided that VISIBILITY starts now and is ungated — the blog is the surface that decision needs and it does not exist yet. This ticket is the MACHINERY plus two concrete first posts; the strategy, the audience and the one-shot launch guard all live in that ticket and are not relitigated here."
status: backlog
---

# `/blog/` is `Coming soon.` — the one channel that fixes the reputation penalty

Found 2026-08-27 during the machine-legibility audit
([[feature-web-machine-readable-project-metadata]]).
**Fix lands in the private `~/pxx-website` repo, not this checkout.**

## Read [[feature-promo-launch-plan]] first — this ticket is downstream of it

That ticket (designed 2026-07-12) already settles the strategy, and nothing
here overrides it. Its three-way split is the part that governs this work:

> **Visibility != release != launch.** Visibility is continuous, cheap,
> compounding — devlog, a legible repo, occasional posts. **Start NOW.** The
> launch is **one-shot** and **USER-TRIGGERED ONLY**.

**Everything in this ticket is visibility, not launch.** Shipping the blog and
posting to it is explicitly the ungated half. Submitting anything to HN is the
one-shot moment and is the user's call alone — do not let "we finally have a
blog" become the trigger for it. There is roughly one first impression with the
compiler crowd and a front-paged post landing on a broken install burns it.

The launch plan also already has the hook, and it is better than the framings
below: a self-hosting multi-frontend compiler, largely AI-written, with a
falsifiable byte-identical self-host fixedpoint, compiling SQLite libc-free on a
microcontroller. Use that framing; the two posts below are the material that
makes it credible in advance rather than a replacement for it.

## The problem this is actually solving

The project is hitting a new-domain discovery penalty — at one point a Google
AI answer declined to treat pxxc.org as reputable, and the response was
retracted only after a complaint. The audit shows this is **not** a technical
problem: the site is server-rendered, crawlable, indexed (a cold search
surfaced `/`, `/contribute/`, and a deep `/status/done/` page), correctly
summarised, and has a valid sitemap. Nothing on-site is blocking it.

What the penalty responds to is domain age and who links to you. It does not
unlock via traffic or via metadata. It unlocks via a small number of citations
from places that already carry authority — one HN front page, one lobste.rs
thread, a Wikipedia citation, a distro package.

Which means the binding constraint is **something worth citing**, and the site
currently has a `Coming soon.` sign on the only place that could hold it.

## Scope split

- **Track W (this ticket):** the blog machinery — post rendering, index,
  permalinks, dates, the Atom feed from [[feature-web-syndication-feeds]],
  and a house style for code blocks that matches the docs.
- **Not Track W:** the post content. Authorship is the user's call — same rule
  [[feature-promo-launch-plan]] sets for outreach. Two proposals below,
  recorded here so the machinery is not blocked on inventing a topic.
- **Also not Track W:** [[docs-devnotes-ai-assisted-build]] holds the framing
  for the AI-written angle, including the nuance the launch plan warns must not
  be flattened ("this was not 'prompt and see'"). Post 1 below should be built
  on that, not written from scratch.

## Two visibility posts whose material already exists

### 1. The one only this project can write

A compiler built by a fleet of parallel agents: file-lanes so concurrent
sessions do not clobber each other, a watcher publishing per-sha verdicts, a
rule that agents file decisions rather than guess them, and a pin that holds a
repo-wide lock. Every current argument about multi-agent development is
conducted with opinions; this project has production data and a **public,
live-updating `/status/` feed that lets a reader verify the claim themselves**.
That combination is rare enough to be the whole post.

### 2. The one with a sharp edge in it

The `-O0`-only self-compile failure that passed the entire gate and was caught
by a benchmark — recorded in `CLAUDE.md`'s claims-discipline section and in
[[bug-a-the-selfhost-rule-is-a-no-op-when-the-seed-is-newer-than-its-sources]].
"Our gate proved the compiler reproduces itself at one optimisation level, and
we read it as proof that it reproduces itself" is a genuinely good engineering
story, and the fact that the project wrote its own miss down in its own docs is
the part that earns the link. Technical audiences cite candour about a subtle
gate hole far more readily than they cite a feature list.

## Claims discipline

Blog posts are exactly the surface `CLAUDE.md` names — public-facing copy where
"terse styles drop the qualifying words first". Post 2 in particular circles
the byte-identical claim and must state the scope every time: the fixedpoint is
the **binary** reproducing **our own previous output at the default `-O`
level**, and the zlib result is the **program's output** matching a
**gcc-built** zlib's. Never "byte-identical to gcc".

## Gate

Blog renders, permalinks are stable, feed validates, and the first post has been
read by the user before it ships.

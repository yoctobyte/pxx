---
prio: 45
blocked-by: [decide-1-0-scope-promise]
---

# Promo & launch plan — visibility now, launch at 1.0

- **Type:** feature (outreach)
- **Track:** W (website) — with Track D (docs) touchpoints
- **Status:** backlog — designed 2026-07-12.
- **Owner:** —
- **Blocked-by:** decide-1-0-scope-promise  (the *launch* is gated; the *visibility* work is not)
- **Related:** [[docs-devnotes-ai-assisted-build]], [[feature-web-track-w-bootstrap]]

## The core distinction
**Visibility ≠ launch.** They are different resources and must not be conflated.
- **Visibility** is continuous, cheap, compounding: devlog, a legible repo, occasional posts.
  Start NOW. Staying invisible until 1.0 throws away years of compounding.
- **Launch** is **one-shot**. There is roughly one "Show HN: pxx 1.0" and one first impression
  with the compiler crowd. Spend it on something that survives an hour of hostile clicking.
  **Launch at 1.0, not before.**

## The hook (what the story actually is)
"Another Pascal compiler" is a nostalgia item — that framing earns 40 upvotes from people who
miss Turbo Pascal, and zero contributors. The real story:

> **A self-hosting, multi-frontend compiler, largely AI-written, with a byte-identical
> self-host fixed point that proves it — and here it is compiling SQLite, libc-free, on a
> microcontroller.**

Why that lands: it sits in the middle of the most contested argument in software, and — unlike
essentially every "I built X with AI" post — **it is falsifiable**. The evidence is mechanical:
the fixed-point gate, 200+ pins, a public decision record, a cross-target matrix. People will
try to poke holes. That IS the attention. See [[docs-devnotes-ai-assisted-build]] for the
framing and the nuance that must not be flattened ("this was not 'prompt and see'").

Supporting credibility (state PRECISELY — see CLAUDE.md "Claims discipline"):
- **tcc self-compiles under pxx**; SQLite and Lua run; zlib built with pxx produces compressed
  output byte-identical to a gcc-**built** zlib's (behavioral parity — NOT gcc codegen parity).
- **libc-free**, six targets, runs on an ESP32.

## Audience
Not primarily the Pascal community (small, content with FPC — they will find us anyway and are
a welcome secondary). Aim at **compiler people** and **the AI-engineering crowd starving for a
real artifact** instead of another demo app.

## "Why does the world need another compiler?" — have an honest answer ready
It will be the top comment. Do NOT answer "it's faster" (it isn't, and they will benchmark
within the hour). The honest answers, which are good ones:
- **Small enough to understand.** One IR, thin frontends, no autotools, no libc, readable source.
- **One substrate, many languages** — Pascal/C/(Rust/Zig) lowering to a shared IR; add a frontend
  without rebuilding the world.
- **Freestanding by default** — same compiler from x86-64 Linux down to a bare-metal ESP32.
- **And the existence proof** — that this class of systems work is now reachable this way, with a
  gate that proves it rather than a vibe that asserts it.

## Plan

### Now → 1.0 (compounding, near-zero cost)
1. **Devlog.** The raw material is a *byproduct* of the record we already keep (tickets, session
   notes, decision rationale). A periodic "what broke and how we fixed it" post is the highest-
   leverage channel for this project and the one that attracts the interested minds the user
   actually wants. Compiler people love bug post-mortems — and ours are genuinely good.
2. **Make the repo legible in 30 seconds.** README answering *why does this exist* in five lines,
   above the fold, plus one copy-pasteable demo. Drive-by visitors decide inside that window.
3. **One flagship demo** runnable in under a minute. Candidate: pxx compiling SQLite, libc-free,
   and running it. That is a sentence that stops a scroll.
4. Docs + install must actually work — see the launch gate below.

### At 1.0 (the one shot)
5. **Working install first.** A launch where `curl | sh` fails is a launch you do not get back.
6. Coordinated, same day, midweek morning US time: Show HN + lobste.rs + r/programming +
   r/compilers (+ Pascal forums as secondary). **Be present in the comments all day** — for the
   first 24 hours the comment thread *is* the product.

## Three things not to do
- **Do not hide the AI angle.** The commit trailers say it anyway. Surfacing *after* launch looks
  like concealment and poisons everything. Lead with it — it is the differentiator.
- **Do not overclaim.** No "faster than gcc". No "byte-identical to gcc". One caught overclaim
  costs more than the claim ever gained.
- **Do not launch before docs + install work.** Amazing code is invisible if the first five
  minutes are broken.

## Log
- 2026-07-12 — designed. Take-off is expected to be slow and that is fine; the visibility work
  compounds while 1.0 is built.

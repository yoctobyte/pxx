---
slug: bug-t-the-o-level-sweep-never-sees-the-third-party-corpus
title: "optdiff sweeps our own test tree only, so the most realistic code is the least O-swept"
track: T
type: bug
prio: 60
status: backlog
found: 2026-08-30
found-by: frank-user, measuring what "all tests passed" covers for an optimization
summary: "tools/optdiff.sh diffs -O0/-O1/-O2/-O3 output across 1960 programs from our own test tree and has ZERO references to library_candidates/ or external/. So lua, sqlite, quickjs, zlib, duktape and tcc are compiled at the default level only and are never diffed across O levels. The owner's proof rule leans on the target set being complex enough to constitute a proof — and the part of it carrying that weight is exactly the part the O-level sweep does not reach."
---

# The O-level sweep never sees the third-party corpus

## Measured

`tools/optdiff.sh` builds its file list from our own test tree (the `.pas` and
`.c` sources under `test/`) — **1960 programs**, four levels, diffed on
stdout+stderr+exit code. Good instrument.

`grep -c 'library_candidates\|external/' tools/optdiff.sh` → **0**.

So the corpus that the full tier compiles — lua, sqlite, quickjs, zlib, duktape,
tcc, cjson, enet, cglm, stb, zengl, the FPC RTL and testsuite, synapse — is built
at the **default level only** and never compared across `-O0/-O1/-O2/-O3`.

## Why it matters more than it did yesterday

The owner ruled 2026-08-30 that **self-host + all tests passed = proof**, with
the reasoning that *the compiler and the target set are themselves complex enough
to constitute one.* That reasoning is sound — and the weight sits on the
third-party corpus, because that is where the un-idiomatic, un-anticipated code
is. **Our test tree is code we wrote to test ourselves; the corpus is code that
does not know we exist.**

An `-O3` miscompile of a pattern nobody on this project would write is exactly
what the corpus is for, and it is the one sweep the corpus never gets.

## What to build

**Extend `optdiff` to a corpus tier, or add a corpus-aware shard set.** The hard
parts are known and are why this is not a one-liner:

- Corpus programs are **not standalone-runnable** the way our own test sources
  are; many are libraries with their own harnesses. The diff needs a per-tree
  notion of "run it and capture output".
- Wall time. `optdiff` is already 300-600 s over 12 shards; the corpus is much
  larger. This probably wants its own tier and its own idle slot rather than
  bolting onto `opt`.
- Nondeterministic output. `tools/optdiff.skip` has 18 patterns for our tree; a
  corpus will need its own, and they will be discovered the hard way.

**Start with the subset that already runs standalone under the full tier** —
those have a known invocation and a known-good output, which is most of what a
diff needs.

## Related

- `bug-t-nothing-checks-that-two-hosts-run-the-same-suite` — the other half of
  "what does a green actually cover", found the same evening.
- `decided/decide-the-o3-tier-is-34-percent-faster-and-nothing-gates-it` — the
  ruling this serves, and the three limits on `opt` measured with it.

**Do not read this as an argument against the ruling.** It is an argument for
making the suite match what the ruling already assumes it is.

## Filing note

The first attempt to write this ticket was **refused by
`.claude/hooks/no-full-suite.sh`**, because the body quoted `optdiff.sh`'s file
list literally and that reads as a shell loop over a test glob. Fourth recorded
instance of that false positive, and the third where the refusal landed on a
document *about* the thing rather than on the thing. Paraphrasing cost one
rewrite, which is exactly the argument for leaving the hook alone: a false
positive costs a rephrase, a false negative costs ten minutes.

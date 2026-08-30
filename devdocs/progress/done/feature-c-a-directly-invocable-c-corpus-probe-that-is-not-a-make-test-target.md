---
slug: feature-c-a-directly-invocable-c-corpus-probe-that-is-not-a-make-test-target
track: C+B
prio: 60
type: feature
blocked-by: []
summary: "A C-lane agent making a C-wide change cannot measure it: every whole-program C target is a `make test-*` the no-full-suite hook refuses, so the evidence is whatever small tests it wrote, then a push and a hope. Give the lane a script that diffs a handful of real C programs against gcc in a couple of minutes."
status: done
owner: frankC
---

# A directly-invocable C corpus probe that is not a `make test-*` target

Spun out of [[idea-c-realworld-test-targets]] (the brainstorm parent, which
stays open — this is one concrete item from it, not the whole idea).

## The hole, which is structural rather than a missing nicety

The C lane's real-world coverage is real and it is all shaped the same way:
`make test-zlib`, `test-lua`, `test-quickjs`, `test-tcc`. Every one of those is
refused by `.claude/hooks/no-full-suite.sh`, and refused **correctly** — they
cost ten minutes each, and Track T sweeps them against the pushed sha anyway.

The consequence nobody wrote down: **a Track C agent that changes something
C-wide has no way to measure it.** Not "an expensive way" — no way. The token
stream, the preprocessor, the struct-member parser all touch every C compile,
and the agent's entire evidence base is the small tests it wrote for the bug it
was fixing, after which it pushes and hopes T catches the rest.

This session is the worked example. The `tkEOF` root fix
([[bug-c-an-unterminated-construct-parses-past-eof-into-the-appended-pascal-builtins]])
set `MainProgramTokCount` in `CLexAll`, which changes the token stream of
**every C program the compiler will ever compile**. The evidence shipped with it
was twelve small programs and nine `test-core` rows. That is good evidence about
the bug and it is nearly no evidence about the blast radius, and I said so in the
commit because saying so was the only instrument available.

## What this is not

- **Not `tools/gcc_diff_probe.sh`.** That answers *"does this call agree with the
  oracle"* across hundreds of small cases, and it is the right tool for that
  question. This answers *"do substantial programs still build, run and agree"* —
  a different question, and the one a C-wide change raises.
- **Not a replacement for T's corpora.** zlib/lua/quickjs/tcc stay exactly where
  they are. This is the fast pre-push check that makes the push worth T's time.
- **Not a `make` target,** deliberately. The moment it becomes `make test-ccorpus`
  it is one rename away from being swept into the refused set, and the whole point
  is that it is the thing a C agent is *allowed* to run.

## Shape

`tools/c_corpus_probe.sh [--pinned] [--keep] [pattern]`

For each program: build under `gcc -std=c99` and under pxx, run both, compare
stdout+stderr and exit code. One line each. Runs in seconds.

**The oracle is gcc, so a program gcc cannot build is a SKIP** — counted,
printed, and named with gcc's own first lines. A silent skip is how a disarmed
case sits for months looking like coverage; that rule is already written into
`gcc_diff_probe.sh`'s header and this inherits it.

**The corpus is built-in and self-contained.** `gate.sh quick` asserts no vendor
tree is tracked, so nothing third-party is committed. `test/ccorpus/*.c` are
programs written for this: whole programs with deterministic output, not
assertions. Real single-file libraries (stb, cJSON, miniz — the parent's
"palate cleansers") are picked up from `$PXX_C_CORPUS_DIR` when an operator has
fetched them, and its **absence is printed with the path it looked for**, the
way `make test-lua` reports a missing lua tree rather than passing vacuously.

**The last line is a positive token the probe itself emits:**

```
C-CORPUS-PROBE-COMPLETE programs=6 identical=3 skipped=1 failed=2
```

Not a status for the caller to read. A status can be produced by something that
is not the subject — a `;`-list's last command, a pipe's right-hand side, a
shell that never ran the probe — and every one of those looks like success
(see [[feature-a-a-refusal-is-a-claim-with-a-date-on-it]], the exit-code face).
If that line is absent you did not get a result, whatever the exit code says.

## Gate

Its own five arms, each demonstrated firing rather than assumed:

| arm | how it was proven |
| --- | --- |
| SAME | the three shipped programs, byte-identical to gcc |
| DIFF | a program branching on `__GNUC__` (gcc defines it, pxx does not) |
| SKIP | a program that is not C at all, so gcc refuses it |
| FAIL (exit code) | the same `__GNUC__` split returning 3 vs 0 |
| FAIL (build) | a GNU nested function — gcc builds it, pxx does not |

The first negative controls used `__PXX__`, which does not exist, so DIFF and
FAIL silently reported SAME — **the probe's own failure arms were, briefly, the
disarmed coverage the probe exists to prevent.** Recorded here because it is the
same class the SKIP rule guards, met one level up.

## Related

- [[idea-c-realworld-test-targets]] — the parent; its candidate list is what
  `$PXX_C_CORPUS_DIR` is for
- [[feature-c-cross-lua-sqlite]] — the proven real-program pattern this feeds

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.

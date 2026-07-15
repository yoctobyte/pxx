---
summary: "lib-test flaky: console_solitaire 'aq' smoke prints moves=0/1/2 across runs despite fixed seed NewGame(1) — input-read timing, fails the moves=2 expectation intermittently"
type: bug
track: B
prio: 45
---

# lib-test: console_solitaire smoke is flaky (moves=0/1/2, expectation moves=2)

- **Type:** bug (flaky gate — Track B's `make lib-test` can red spuriously).
- **Found:** 2026-07-15 while smoking the v221 pin. NOT a pin regression: the
  PREVIOUS pinned binary (git HEAD~1 stable_pinned) shows the same variance.

## Symptom

```
$ for i in 1 2 3; do printf 'aq' | /tmp/console_solitaire | tail -1; done
moves=1 won=FALSE
moves=0 won=FALSE
moves=2 won=FALSE
```

Makefile lib-test expects `moves=2 won=FALSE` (line ~5017), so the gate reds
~2/3 of the time.

## Analysis

The deal is deterministic (`NewGame(1)`, klondike RandSeed(seed) shuffle), so
the variance is in INPUT handling, not the game: `printf 'aq'` with no newline
into whatever raw/nonblocking key read the console UI does — sometimes only
one key (or none) is consumed as a move before EOF. Timing-dependent.

## Direction

Make the smoke deterministic: blocking reads until EOF (treat EOF as 'q'), or
a `--script` input mode for the smoke, or drive it with a pty/expect. Fix the
PROGRAM's input loop or the TEST harness — not the expectation.

## Acceptance

`for i in $(seq 20); do printf 'aq' | ...; done` prints `moves=2 won=FALSE`
20/20; `make lib-test` green repeatedly.

## Log
- 2026-07-15 — resolved, commit c80ec4e7.

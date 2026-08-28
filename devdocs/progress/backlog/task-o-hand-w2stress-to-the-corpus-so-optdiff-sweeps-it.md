---
slug: task-o-hand-w2stress-to-the-corpus-so-optdiff-sweeps-it
title: "Hand w2stress.pas to the test corpus, where optdiff already sweeps every level forever"
track: A
prio: 40
type: task
blocked-by: []
status: backlog
owner: ""
created: 2026-08-28
summary: "Track O wrote w2stress.pas for c93292fe4 and asked for a bespoke four-level agreement harness to run it. The harness already exists -- tools/optdiff.sh sweeps every standalone test program at -O0/-O1/-O2/-O3 in 12 shards -- so the program only needs to land in the corpus to be swept forever, with no new machinery. Cheapest item of the three the -O3 ticket resolved into, and the one with the most value for the register-pressure campaign, since the corpus is broad but not dense in in-place ALU shapes."
---

# What is being asked

Drop `w2stress.pas` (written for `c93292fe4`, currently in the W2 scratchpad)
into the test corpus as an ordinary standalone test program. Nothing else is
needed: `tools/optdiff.sh` globs every standalone `.pas`/`.c` in the corpus,
shards it 12 ways, and compares stdout+stderr+exit code at `-O0`, `-O1`, `-O2`
and `-O3`. Once the file is in, it is swept at every level on every `opt` phase,
forever, with no sidecar table and no expected-output file to maintain.

This is Track O's own program and Track O's file to place, which is why it is
filed here rather than done by T.

# Why it is worth doing

`optdiff` covers the corpus broadly but not *densely* in the constructs the
register-pressure campaign actually changed. `w2stress.pas` is deliberately dense
in exactly those: all five in-place ALU ops at every integer width driven past
their wrap point, signed and unsigned narrowing, self-referencing assignment,
non-commutative `x := x - y`, `{$Q+}`, in-place stores inside `try/except`, `var`
and value params, pointer arithmetic.

The campaign's own near-miss is the argument. frank-optimize-b4's first W2 build
silently refused the hottest shape in the language — it guarded on IR node types,
and a for loop's own increment carries `tyUnknown`, so it fired on `s := s + j`
and not on `i := i + 1`. Half the win, every output byte-identical, every test
green, caught only by disassembling. A dense program in the sweep does not catch
a *missing* optimisation either — nothing in a correctness suite can — but it is
where a wrong one would show up first.

# Notes for whoever places it

- **The `{$Q+}` trap does not apply here.** The program's FPC-oracle problem —
  pxx detects a LongInt overflow that `fpc -O2` misses, recorded in
  `devdocs/dev/pascal-dialect-divergences.md` — only bites a differential harness
  with an *external* oracle. `optdiff` has none: the other levels are the oracle.
  That is the reason to prefer this route over an FPC differential, and it is
  Track O's own reasoning from the originating ticket.
- If any level legitimately diverges (nondeterministic output, timing), the sweep
  has `tools/optdiff.skip` for named patterns with a reason — but a real
  divergence here is a codegen bug and should be filed, not skipped.
- It must be **standalone-runnable** and terminate well inside the 30s base
  timeout, or the sweep records it as a skip.

# Provenance

Resolved out of `chore-t-nothing-in-the-matrix-runs-o3-so-no-failures-is-unfalsifiable`,
whose central premise (that nothing in the matrix compiles at `-O3`) was refuted
by measurement: `opt` has run 701 times, has gone non-GREEN 30 times, and four
`-O3` bugs in `done/` came from it. Two of that ticket's three real items were
done by Track T; this is the third, and it belongs to O.

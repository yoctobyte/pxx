# IR correctness fuzzer — cross-target differential + mutation-seeded

- **Type:** feature (Track A — compiler/tools infrastructure)
- **Status:** working (taken 2026-07-05)
- **Track:** A
- **Owner:** Claude (~/frank2)
- **Opened:** 2026-07-05 (design discussion: language-target frontends are a
  side effect, the real goal is proving AST/IR correctness — this is the
  direct tool for that goal, replacing "one more exotic frontend" as the
  primary lever)

## Motivation

The esoteric-frontend-probe line of work ([[feature-esoteric-frontend-probes]])
established that novel-shaped programs find real shared-internals bugs (the
Rust skeleton surfaced `bug-selfhost-multifn-ifelse-miscompile`; the C
frontend's bring-up did this repeatedly). But each new frontend buys exactly
one hand-written test program per real implementation effort — a very
expensive way to generate test cases when the actual goal is "prove AST/IR
correctness," not "compile language X."

A fuzzer buys unlimited test cases for one build cost. This ticket builds one
targeting the 4 core frontends ([[feature-esoteric-frontend-probes]]'s "Core
vs opportunistic" split: Pascal, C, BASIC, Nil-Python), starting with Pascal
since it's the primary, best-understood surface.

## Design (settled in discussion, 2026-07-05)

**Fuzzer and regression suite are producer/consumer, not rivals.** `make
test` stays the fast, always-on, deterministic gate — nothing about it
changes. The fuzzer runs out-of-band (background/scheduled/time-boxed),
never blocks a commit, and its entire output is: either nothing (clean run),
or a new permanent regression test once a found bug is minimized and fixed —
the same way every existing `bug-*.md` in `done/` already has a `test/test_*.pas`
backing it today. This just automates *finding the next one*.

**Oracle — two, both free, no new infrastructure needed to start:**

1. **Cross-target differential.** PXX already builds the same source for
   x86-64 (native) / i386 / aarch64 / arm32 / riscv32, and `tools/run_target.sh`
   already runs the cross ones under QEMU user-mode (confirmed installed:
   `qemu-i386`, `qemu-aarch64`, `qemu-arm`, `qemu-riscv32`). Compile a
   generated/mutated program for every target, run each, diff stdout — any
   divergence between native and emulated output is a real backend/codegen
   bug. Direct precedent: Csmith (random C generator + differential testing
   across compilers) — this project already has the multi-target half of
   that setup, just needs the generator half.
2. **Self-host-fixedpoint-shaped consistency** (secondary oracle, add once
   [[feature-optimization-levels]] or similar exists): same generated program
   compiled with different codegen paths/flags must produce identical runtime
   output. No external reference compiler needed either way — both oracles
   are internal-consistency checks, which is what makes this tractable
   without a second Pascal implementation to diff against.

**Generation — seed-and-mutate, not grammar-from-scratch (v1):**

- Seed corpus: the existing 629 `test/*.pas` files. These are already valid,
  already exercise real language features, already known-good (their expected
  output is implicit — running unmutated is the baseline).
- Mutate: small, localized edits (swap an operator, perturb a constant, alter
  a loop bound, reorder independent statements, change a type reference,
  toggle a boolarg) — cheap to generate, far more likely to hit valid-but-weird
  states than a from-scratch grammar generator, and reuses code the project
  already trusts as a starting point.
- v1 explicitly skips: fully generative grammar-based fuzzing (a bigger,
  separate investment — v2 material), coverage-guided mutation (needs
  compiler instrumentation — also v2).

**Minimization:** on a found divergence, delta-debug the mutated file down
(remove/simplify lines while the divergence still reproduces) before filing —
keeps triage cheap regardless of how noisy generation is.

**Time-boxing:** run for a fixed wall-clock budget per invocation (e.g. `tools/
fuzz.sh --minutes 20`), not "run forever." A clean run within budget is a
successful, informative result (confirms robustness for whatever mutations
were tried), not "no more bugs exist."

## Explicit non-goals (v1)

- Not a grammar-based generator from scratch — mutation-of-corpus only, v1.
- Not coverage-guided — no compiler instrumentation added for this.
- Not continuous/CI-blocking — background/scheduled only, never gates a commit.
- Not targeting C/BASIC/Nil-Python yet — Pascal first (primary surface, largest
  seed corpus); extend to the other 3 core frontends once the harness proves
  out on Pascal.
- Not fuzzing esoteric-probe frontends (Ada/Algol/Fortran/COBOL/Zig/Erlang/
  LOLCODE/Whitespace) — those stay hand-written skeletons per their own
  tickets; this fuzzer only targets the core 4.

## Scope / sub-steps

1. **Harness v1** — `tools/fuzz.sh`: pick a random seed file from `test/*.pas`,
   apply N small random mutations, compile for x86-64 + cross targets, run
   each via `tools/run_target.sh`, diff stdout across targets. Time-boxed loop.
   Log every mutation tried (even clean ones) to a scratch file for later
   corpus/coverage analysis, even though v1 doesn't act on coverage yet.
2. **Minimizer** — on a divergence, delta-debug the mutated file (remove
   lines/simplify while divergence persists) before reporting.
3. **Triage-to-ticket path** — a minimized divergence becomes a new
   `bug-*.md` (urgent, Track A) + a permanent `test/test_*.pas` regression
   test, same as every existing bug in `done/`.
4. **Extend to C/BASIC/Nil-Python** seed corpora once Pascal harness proves
   out (each frontend already has its own `test/*.c`/`*.bas`/`*.npy` files to
   seed from).

## Acceptance

`tools/fuzz.sh` runs for a bounded time budget, exercises real mutations
against the existing corpus across all 5 targets, and either reports a clean
run or a minimized reproducer. At least one real run completed and logged
here, whether or not it found anything (a clean run is a valid, useful
result, per the inverted-success-criteria pattern established for esoteric
probes — this fuzzer follows the same spirit for a different technique).

## Log
- 2026-07-05 — filed and taken directly (Track A, no other agent concurrently
  holds it this session). Confirmed cross-target QEMU tooling already
  installed and working (`tools/run_target.sh`, all 4 QEMU binaries present)
  and the seed corpus size (629 `test/*.pas` files) before committing to the
  design above.

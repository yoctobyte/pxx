# Starter prompt — Claude B (libraries / demos track)

Paste this into the second Claude agent to put it on track B.

---

You are **Claude B** on the frankonpiler project — the **libraries & demos**
track. A second agent (Claude A) is working the compiler in parallel on this same
repo/branch; stay out of `compiler/**`.

Read `docs/dev/parallel-tracks.md` and `CLAUDE.md` first — they define the track
split, the stable-compiler boundary, and shared-checkout coordination.

Your rules:
- **Build everything with the pinned stable compiler**, never rebuild the
  compiler: `$(PXX_STABLE)` = `stable_linux_amd64/default/pinned` (currently v9).
  `pinned` only moves when A runs `make pin`, so your compiler is stable mid-task
  even while A keeps stabilizing. Use `make lib-test` (curated green smoke) and
  `make demos` (compile-smoke dashboard). Do NOT run `make bootstrap` / edit
  `compiler/**`.
- **Own** `lib/rtl`, `lib/pcl`, `examples/**`, and new `test/lib_*`. Add your
  build/test steps to the fenced "Library / demo track" block in the `Makefile`.
- When you hit a **compiler or language gap** (a missing operator, a parser
  error, a codegen bug), do not work around it silently — **file a ticket** in
  `docs/progress/backlog/` (Claude A picks it up) and pick a different library
  task that the current stable already supports.
- If the pinned stable lacks a feature you need and there's a ticket for it,
  check `stable_linux_amd64/default/history.log` (checkpoints) and `pin.log`
  (blessings); ping the user to ask A to `make stabilize && make pin` once it
  lands.

Coordination: work on `master`, commit in small units, `git pull --rebase`
before pushing, push promptly. `git log --oneline -5` at start to see what A just
landed (e.g. a new stable vN).

First tasks (backlog, in rough priority):
1. `lib-intToStr-missing` — `IntToStr` in `lib/rtl` (unblocks examples/primes).
2. `lib-string-copy-trim-missing` — `Copy` / `Trim` (unblocks examples/adventure).
3. Then the library features B already scoped: `feature-json-library`,
   `feature-hashing-library`, `feature-bignum-library`,
   `feature-compression-library`, `feature-sat-solver-library` — each has a
   paired demo app as its acceptance oracle.

Goal each session: grow `lib-test` green and turn `make demos` FAILs into OKs,
filing compiler tickets for anything that blocks you. Acceptance for a library =
its paired test/demo app compiles+runs correct output against the pinned stable.

---

(Keep this file updated as the backlog priorities shift.)

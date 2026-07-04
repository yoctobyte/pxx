# Handover 2026-07-04 — Track A (compiler), fresh-context continuation

You are **Track A (compiler)** on frankonpiler, working directly on `master`.
Read `CLAUDE.md` + `devdocs/dev/parallel-tracks.md` + your auto-`MEMORY.md`
first. This continues a session that wound the optimization arc down and did
backlog cleanup; everything is pushed, tree clean, gates green.

## State (verified end of 2026-07-04 session)

- **Pin = v171**, `-O1`-built and **transparent** (an -O1-built compiler emits
  byte-identical -O0 output, so B/C/D see no change). `make test` green, `-O0`
  self-host **byte-identical**, `make lib-test` + 19 demos green.
- **Rust frontend merged to master** by Track R / "sis" (rlexer/rparser +
  enum/match/generics). It is a **parallel track** — do NOT touch
  `compiler/rlexer.inc`/`rparser.inc` or Rust tickets; that's sis's lane.
- `MAX_GLOBFIX` was bumped 32768→65536 (the Rust merge grew the compiler past
  it; `--threadsafe` self-compile overflowed). FPC cold-bootstrapped, green.

## Optimization arc — DELIVERED (context, not new work)

`feature-optimization-levels` moved working→backlog. `-O1` shipped: emitter
peepholes (passes 1-4: operand direct-load, compare-into-branch fusion),
imm-fold, and a **shared-IR pass pipeline** (`IROptimize` in ir.inc) with
DCE + redundant-jump (all-target, all-frontend). Const-fold / algebraic
identities / if-false DCE / strength reduction were **measured 0-fire and
rejected** (frontends pre-eliminate upstream) — guarded by a tripwire
(`IROptWarnMissedFold`). Full method + file map:
**`devdocs/dev/optimization-architecture.md`**. -O2/-O3 currently alias -O1.

## Next Track A work — pick the depth item (recommended: regcall -O2)

**1. Register calling convention (`-O2`) — the big self-compile win.**
Ticket `feature-callconv-register-args` has the **design + register audit +
phasing done this session** (read it fully). Summary: park non-address-taken
scalar params in callee-saved regs (skip the spill + per-use reload; callee-
saved survive calls by ABI so no cross-call spill). `r14`/`r15` are ZERO-use in
x86-64 codegen (safe now); `rbx`/`r12`/`r13` used only in save/restore-
disciplined helpers (safe after audit). Gated behind `-O2`; `-O0`/`-O1`
untouched. **Start at phase 0**: fix the opportunity-measurement instrumentation
(a first attempt printed 0 — `CurProc` validity/timing at the probe site;
the analysis is sound, probe placement was off), MEASURE how many params are
register-eligible, THEN phase 1 (r14/r15 residency). This is FPC's ~2× lead;
it's the main remaining pin-time win.

**Other Track A candidates (smaller):**
- `feature-selfhost-guard-ir-unsupported` — make `IRVerify` reject
  `IR_UNSUPPORTED` (measured 0 on mature frontends). **Gated on Track R** (their
  in-dev Rust frontend legitimately emits it) — land as opt-in flag first or
  coordinate with sis. Would've caught the else-if miscompile at compile time.
- `bug-c-printf-without-stdio-include-varargs` — the planned stub-delete fix is
  DEAD CODE now (mechanism moved since v152); real fix needs finding where
  printf auto-resolves (implicit path that drops varargs / silent-swallows the
  extern). Deeper than low-hanging — re-scope first.
- `feature-opt-store-reload-elimination` — blocked on the same liveness scaffold
  regcall builds; do it after/with phase 0's addr-taken analysis.

## Rules (non-negotiable)

- `-O0` self-host byte-identity is **sacred** — every opt gates `OptLevel >= tier`.
- Per-pass rhythm: implement → `make test-opt` → `-O0` fixedpoint → full
  `make test` under an -O1(or -O2)-BUILT compiler (swap binary, `touch`, test,
  restore) → hyperfine → commit small → `make PXXFLAGS=-O1 stabilize` + `make
  pin` (pins are -O1-built) → push. Run slow steps as SEPARATE visible commands
  (chaining stabilize+pin+push hit a 10-min wall).
- **Measure before building** — const-fold/identities/if-false-DCE/strength-
  reduction all measured 0-fire; don't ship no-op passes. Same for regcall
  (phase 0 measures the opportunity first).
- Autoproceed on queued steps; answer questions in a tool-free turn (his client
  drops text above tool storms). Don't manufacture risky churn against a clean
  tree.

## Cross-track flags (don't fix, just know)

- `bug-selfhost-multifn-ifelse-miscompile` is FIXED (sis's else-if fix, repro=20)
  but still sits in `working/` no-owner — the last `progress.sh check`
  violation. Sis's to move to `done/`.
- User leans **depth over breadth**: Zig ticket-only (`feature-zig-frontend`,
  shares hard parts with Rust), JS + R parked (dynamic-runtime wall). The 9 open
  `feature-rust-*` sub-tickets are Track R's roadmap (prune = sis's call).

## After Track A: Track B

Track B (lib/rtl, demos) is green (lib-test + 19 demos vs v171). Backlog Track B
items exist (e.g. `task-sqlite-libc-free-runtime-bringup`, eliah IDE) but Track
A depth (regcall) comes first per user.

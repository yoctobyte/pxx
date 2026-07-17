---
summary: "NilPy differential fuzzer — generate NilPy programs, diff pxx output against CPython as oracle"
type: feature
prio: 40
---

# NilPy differential fuzzer (vs CPython)

- **Type:** feature (Track T — tools & testing; the fuzzing family alongside pasmith/csmith).
  T owns the tool; findings file into the owning lane (N frontend / A IR).
- **Status:** backlog
- **Opened:** 2026-07-17, from the "what's stopping NilPy" review.
- **Related:** [[feature-pasmith-pascal-program-generator]] (FPC oracle, Pascal),
  [[project_csmith_fuzzer_findings]] (gcc oracle, C). This is the **missing third**:
  NilPy has no oracle.

## Why — the least-probed frontend

pxx has adversarial coverage for two of three mainline frontends: **pasmith** (Pascal vs
FPC) and **csmith** (C vs gcc). Both drew real, **silent** bugs — the recurring lesson in
this repo is that every serious frontend/IR bug was silent and only a differential oracle
saw it. **NilPy has no equivalent.** Its "no open bugs" status partly reflects *less
hunting*, not proven correctness. Before leaning hard on NilPy (IDE demo, parallel
for-in, bigger apps), close that gap.

The oracle is free and mature: **CPython**. NilPy is a Python subset — a generated NilPy
program that is also valid CPython can be run through both and its output diffed. (NilPy's
`//`-only division, ≤4 params, range-step-1, etc. constrain the generator to the shared
subset — which is exactly what keeps the oracle valid.)

## Design (steal from pasmith)

- **Typed AST generator over the NilPy subset** — well-typed, terminating, single
  checksum at exit. UB-free by construction is easier here than C (Python semantics are
  tight), but the generator MUST stay inside NilPy's *documented v1 subset* or divergence
  becomes "NilPy doesn't support X", not a bug.
- **Oracle:** `python3 prog.py` vs `pxx prog.npy && ./prog` — diff the checksum.
- **Seeded, reproducible;** findings staged low-noise (reuse the fuzz LEDGER pattern,
  [[feature-t-fuzz-findings-ledger]]), shrunk/triaged before a `bug-*` exists.
- **Triage rule:** a divergence is (a) generator emitted outside the NilPy subset, (b) a
  pxx NilPy bug, (c) a genuine Python-semantics mismatch pxx intends (→ documented, not a
  bug). Same ordered-suspicion discipline as pasmith.

## Acceptance

- `nilpy_smith --seed N` deterministically emits a program valid in BOTH NilPy and
  CPython, printing one checksum. A driver runs both, diffs. One bounded run logged
  (clean or not). A divergence → shrunk repro + ticket in the owning lane (N/A) + a
  permanent `test/test_nilpy_*.npy` regression.
- Gate (T tooling): `tools/testmgr.py --tier full` green; test with quick tiers.

## Non-goals

- Not full CPython parity — the generator targets the intersection subset only.
- Not a CI gate (out-of-band, opportunistic — same contract as pasmith/fuzz.sh).

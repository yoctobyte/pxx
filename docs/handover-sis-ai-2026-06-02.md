# Handover: Resume Python-Ready Variant Work

**Snapshot:** 2026-06-02

Source and regression tests are authoritative. Start with:

```sh
git status --short --branch
git log --oneline -8
make test-nilpy
```

## Latest Delivered Work

- Nested dynamic arrays support scalar, managed `AnsiString`, and recursively
  managed-record bases at any depth.
- `Variant` supports managed-string payload assignment, copying,
  retain-before-release overwrite, local cleanup, and printing.
- Nil Python can widen an inferred slot from integer to string-backed
  `Variant`.
- BigInt policy is documented as late library-backed polish with runtime
  overflow promotion only where Python integer semantics require it.
- Async/coroutine/yield thoughts are parked in
  [`plan-async-coroutines.md`](plan-async-coroutines.md).
- Pascal runtime support now has a conservative token-reachability gate.
  Allocation-free hello emits 287 bytes instead of 1,134. Details:
  [`runtime-emission-size-audit-2026-06-02.md`](runtime-emission-size-audit-2026-06-02.md).
  The gate is intentionally pre-parse and conservative: direct helper-call
  addresses stay available during one-pass body emission.

## Verification Baseline

Passed after the runtime gate:

```text
self-host bootstrap convergence
make test-nilpy
make test
make benchmark
git diff --check
```

Post-gate benchmark: [`bench/2026-06-02-runtime-gate.md`](../bench/2026-06-02-runtime-gate.md).

## Immediate Next Work

Continue making `Variant` Python-ready. Keep changes incremental and test
through Pascal first, then `.npy`.

1. Add managed-string `Variant` comparisons (`=`, `<>`, `<`, `<=`, `>`, `>=`)
   using the existing managed-string comparison machinery.
2. Add `Variant` string concatenation for `+`, including scalar-string boxing
   and correct temporary ownership.
3. Decide and implement the minimal Python-facing conversion behavior needed
   next. Keep BigInt deferred.
4. Add focused Pascal and Nil Python regressions for every new operator and
   overwrite path.

After the operator slice, audit broader Variant ownership surfaces:

- exception-path cleanup;
- params/results;
- aggregate fields and future container elements;
- process-global managed payload cleanup where it becomes observable.

`TAnyBox` remains the slow fallback tier after inline `Variant`; it can stay a
library-level design until the closed Variant set becomes insufficient.

## Deliberately Deferred

- Fine-grained runtime helper emission. The coarse Pascal gate is sufficient
  for now; helper dependency splitting and argv-stack gating are rainy-afternoon
  work.
- Nested dynamic-array sublevel copy-on-write.
- Fresh managed result move semantics.
- Allocator platform refactor, splitting/coalescing, and fixed-arena profile.
- Async/coroutine implementation until Variant, containers, modules, and
  SQLite groundwork are further along.
- BigInt implementation until late compatibility polish.

## Commit State At Handover

Expected latest local commits:

```text
1f9739a perf(runtime): gate unused Pascal support
ea44f62 docs: record runtime emission size audit
8b4f1e7 docs: record June benchmark snapshot
35e6c54 feat(variant): add managed string payloads
ac765a7 docs: plan async coroutine substrate
```

Push status may differ depending on whether the handover documentation commit
has already been published.

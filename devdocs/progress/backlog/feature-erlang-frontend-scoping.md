# Erlang frontend — scoping only

- **Type:** feature — scoping ticket (Track A, once picked up)
- **Status:** backlog — scoping only, no code, not greenlit
- **Owner:** —
- **Opened:** 2026-07-05 (user decision — prioritized ahead of [[feature-zig-frontend]] (parked))
- **Priority:** unranked

## Motivation

User chose Erlang over Zig as the next frontend to *scope* (not necessarily
build first — Rust is already in progress). Reasoning: Zig's `comptime` needs a
recursive, Turing-complete compile-time interpreter that sits in tension with
PXX's byte-identical fixedpoint self-host guarantee (see [[feature-zig-frontend]]
"Why parked"). Erlang's hard parts — actor-model concurrency, pattern matching,
immutable data, the BEAM's preemptive scheduling — are a **different kind of
hard**: none of them require a compile-time-recursive evaluator. They're
runtime/RTL problems (a scheduler, message-passing mailboxes, immutable/
persistent data structures), which is a shape of problem this project already
has some machinery for (coroutine runtime, `coroutine_emit.inc`) rather than a
wholly new compiler-architecture risk.

**This ticket is scoping only** — same posture as the original Rust/Zig
umbrellas before any code: map Erlang's constructs onto existing/needed IR,
identify what's free vs. what needs new shared machinery, before committing to
a build.

## Known hard parts, unscoped (fill in when picked up)

- **Pattern matching** as the primary control-construct (not just `case`/`switch`
  sugar — Erlang function clauses dispatch by pattern, including on message
  receive). Likely shares the generalized tagged-union / pattern-match primitive
  already needed by Rust ([[feature-rust-match-enum-payload]]) and Zig — a
  second consumer would justify building it sooner.
- **Immutability** — Erlang has no mutable variables at all (single-assignment).
  Different discipline than PXX's IR assumes; needs its own scoping pass, not
  free.
- **Actor model / message passing** — processes (green, millions-scale, BEAM-
  style), mailboxes, `receive` with pattern + optional timeout. Needs a
  scheduler; closest existing PXX machinery is the stackful coroutine runtime
  (`coroutine_emit.inc`), but BEAM's preemptive (reduction-counted) scheduling
  is a different model than cooperative coroutines — gap needs honest sizing,
  not assumed-free.
- **Supervision trees / "let it crash"** — process linking/monitoring,
  restart strategies. An RTL-level feature (Track B, once the process model
  exists), not a frontend-syntax problem.
- **Hot code reloading** — a hallmark BEAM feature; almost certainly out of
  scope for a v1 (no equivalent concept anywhere in PXX's static-link/ELF
  model) — flag as an explicit non-goal once this scoping starts, don't let it
  silently block everything else like `comptime` did for Zig.
- **Bit syntax / binaries** (`<<...>>>` pattern matching on binary data) —
  Erlang-specific, no direct PXX equivalent; likely a moderate, self-contained
  addition once bit-level pattern matching exists for the tagged-union work
  above.

## Explicit early non-goals (proposed — confirm when scoping starts)

- Not distributed Erlang (node-to-node clustering) — v1 targets a single OS
  process, same posture as PXX's other frontends.
- Not hot code reloading (see above).
- Not compiling arbitrary existing `.erl`/OTP codebases — hand-port a call
  surface if needed, same rule as C/Rust/Zig's non-goals.

## Acceptance (for this scoping ticket only)

A gap-map table (like [[feature-zig-frontend]]'s "AST/IR gap map") showing what
lowers onto existing IR for free vs. what needs new shared machinery, plus an
honest sizing of the actor-model/scheduler gap specifically (the one part with
no close existing analogue). No code required to close this ticket — only a
scoping doc, same bar as the original Rust/Zig umbrellas before work started.

## Log
- 2026-07-05 — filed per user decision to scope Erlang ahead of attempting Zig,
  given Zig's comptime-determinism conflict with the fixedpoint self-host gate.
  Track A once picked up; not scheduled, not greenlit to build.

# Auto stackless/stackful backend selection

- **Type:** feature
- **Status:** done-followup (big / not directly language-relevant)
- **Owner:** —
- **Opened:** 2026-06-18 (design discussion — async ergonomics on ESP)

> Core (stackless-or-error) is buildable now. Only the cost-warning *upscale* on
> ESP/32-bit is gated on feature-stackful-coro-port (soft dependency, in body).

## Motivation

Today bare `; generator;` / `; async;` always use the **stackful** backend; the
programmer forces the other with an explicit `stackful;` / `stackless;`
directive (see [dialect/generators.md](../../dialect/generators.md)). That pushes
a memory/portability decision onto every call site. The compiler can make it:
prefer the RAM-cheap stackless backend, fall back to stackful only when a
language feature in the body requires it — and say so.

See the design record in
[developer/concurrency-memory-model.md](../../developer/concurrency-memory-model.md).

## Rule (target-aware)

1. **Eligible → stackless.** Eligible = structured suspension points only
   (`yield`/`await` at top level or inside `for`/`while`/`if`; never in
   `case`/`repeat`/`with`, a condition, a `for` bound, or `try`..`except`) **and**
   no managed local (string / dynamic array / record) live across a suspension.
2. **Ineligible → stackful**, but only on a target that **has** the stackful
   backend. On a target without it, **hard error** naming the feature that forced
   the upscale.
3. Where stackful exists, the upscale is a **cost warning**, not silent:
   ```
   warning: async Foo upscaled to stackful (managed local 's' lives across await)
            — costs a ~N-byte heap stack per live instance; ESP RAM is tight
   ```
   Name the trigger + line + the per-instance stack cost.

On a no-stackful target this is effectively **"stackless or a clear error"** —
the correct contract for a no-MMU part (ESP). Explicit `stackful;` / `stackless;`
always override auto.

## Dependencies / sequencing

- Needs the eligibility analysis (largely exists — the stackless backend already
  enforces these restrictions; reuse that checker as the *selector*).
- The cost-warning path for ESP/32-bit is **blocked on**
  feature-stackful-coro-port (until stackful exists on a target, ineligible code
  there must error, not warn). Ship the **stackless-or-error** behaviour first;
  flip ESP/32-bit errors to warnings as each target gains stackful.

## Acceptance

- A generator/async routine with no across-suspension managed locals and only
  structured suspensions compiles **stackless** with no directive.
- An ineligible body on x86-64 compiles **stackful** with a cost warning naming
  the trigger.
- The same ineligible body on a no-stackful target (ESP / 32-bit, pre-port) is a
  **hard error** naming the trigger and the fix.
- Explicit directives still force the backend. `make test` green; cross-bootstrap
  byte-identical.

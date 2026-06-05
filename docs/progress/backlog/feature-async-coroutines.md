# Async, coroutines, and `yield`

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from rainy-afternoon / plan-async-coroutines.md)

## Motivation

A future shared-language arc: one compiler-generated resumable-frame mechanism
plus an event loop and worker pool, usable from Pascal, Nil Python, and future
frontends.

## Scope

Design: `../../developer/plan-async-coroutines.md`.

- Shared state-machine / resumable-frame lowering for suspend/resume.
- Event loop + worker pool runtime.
- `yield` / async surface per frontend.

**Sequencing:** finish Variant, containers, modules, SQLite, and allocator
groundwork first — do not start before those.

## Acceptance

A coroutine/`yield` test suspends and resumes correctly on the shared mechanism;
self-host fixedpoint holds.

## Log
- 2026-06-06 — ticket opened from rainy-afternoon.md.

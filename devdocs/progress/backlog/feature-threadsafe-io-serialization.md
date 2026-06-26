# Statement-level I/O serialization under threads

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-unified-heap-allocator
- **Opened:** 2026-06-06 (from todo.md §2d + rainy-afternoon)

## Motivation

One Pascal `write`/`writeln` currently emits several syscalls, so concurrent
output interleaves. `read`/`readln` share global state, and exception output is
unsynchronized. Threaded programs need statement-atomic I/O.

## Scope

- Serialize `write`/`writeln` at the statement level (one logical statement =
  one atomic emission) under `--threadsafe` / `{$THREADSAFE ON}`.
- Decide locking for shared `read`/`readln` line-buffer state.
- Thread-safe exception output.
- Keep the default (non-threadsafe) path lock-free and short.

Depends on the managed-runtime/thread arc landing first (`threads-todo.md`).

## Acceptance

A multi-threaded write test produces non-interleaved lines under `--threadsafe`;
single-thread output and size are unchanged without it.

## Log
- 2026-06-06 — ticket opened from todo.md §2d.

# Statement-level I/O serialization under threads

- **Type:** feature
- **Status:** backlog
- **Owner:** —
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

## Part of the multithreading epic (2026-06-30)

Umbrella: [[meta-multithreading]]. Invariant: threading is opt-in/off-by-default;
single-threaded self-build stays byte-identical; no libc (Linux syscalls only).

## Progress — 2026-07-02, lock infrastructure LANDED (v146); acceptance blocked

The statement-atomic I/O lock is in and single-thread-verified:

- New IR_IO_LOCK(66)/IR_IO_UNLOCK(67), emitted by AN_WRITE/AN_WRITELN and
  AN_READLN/AN_READ lowering around the WHOLE statement — only under
  `--threadsafe` + x86-64 (matching the threadsafe atomics), so the default
  single-threaded build is untouched (self-host byte-identical, the gate).
- EmitIoLockStubs (ir_codegen.inc): REENTRANT owner-tid spinlock over new
  BSS_IO_OWNER/BSS_IO_DEPTH — gettid(186) per statement (no TLS yet), lock
  cmpxchg acquire (raw bytes — cmpxchg not in the asmtext table yet), plain
  store release (x86 TSO). Reentrancy matters: `writeln(F(x))` where F
  writes takes the lock twice on the same thread — verified no deadlock,
  output order unchanged vs unlocked/FPC. Also guards the shared
  INTBUF/LINE_BUF/PEEK_* scratch for reads.
- Gate so far: test/test_threadsafe_io_lock.pas (--threadsafe, reentrant +
  ordering pin) in make test; suite + test-threads green; pinned v146.

**Acceptance (non-interleaved threaded output) is BLOCKED**: threads that
writeln crash TODAY, pre-existing, even on pinned v145 without this lock —
filed as [[bug-tthread-execute-writeln-crash]] with repro + gdb evidence.
When that is fixed, the two-thread interleave test becomes this ticket's
closing gate. Parking in backlog until then.

## Resolution — 2026-07-02, acceptance met (v147)

The blocker ([[bug-tthread-execute-writeln-crash]]) turned out to be a
constructor-arity stack desync, fixed same day. With it gone the acceptance
holds: test/test_thread_writeln_interleave.pas (two threads x 200
60-char writelns, --threadsafe) = 401/401 atomic lines across runs, and the
same program WITHOUT --threadsafe interleaves ~98% of lines — the lock is
doing exactly the serialization. Wired into make test-threads. Remaining
nice-to-haves (exception-output serialization, futex instead of spin under
contention, cross-target) can ride the epic's later milestones; closing.

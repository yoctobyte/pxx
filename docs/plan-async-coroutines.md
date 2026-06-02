# Plan: Async, Coroutines, And Yield

**Status:** future wish, deliberately deferred  
**Snapshot:** 2026-06-02

Async functions, coroutines, and generators belong to one shared compiler arc.
They are different user-facing contracts over the same underlying mechanism:
the compiler rewrites a resumable routine into a state machine whose live
locals survive suspension.

This is feasible with the existing AST and IR direction, but it is not the
next implementation task. Finish the managed-value, Variant, container, module,
and SQLite legwork first.

## Why This Matters

Many applications use threads primarily to avoid blocking on file, network, or
UI I/O. A shared resumable-routine substrate would provide a cheaper and more
composable alternative while remaining compatible with threads for genuinely
blocking or CPU-bound work.

This should be a compiler capability shared by Pascal, Nil Python, and future
frontends. Do not build a Python-specific async runtime.

## Shared Machine Model

A resumable routine lowers to a heap-backed frame:

```text
state
captured parameters
locals live across suspension points
result or yielded value
exception state
continuation / waiter list
```

Each suspension point becomes:

1. Store live locals into the frame.
2. Record the next resume state.
3. Return control to the scheduler or caller.
4. Resume later by dispatching on the saved state.

The compiler should perform liveness analysis conservatively at first: spill
all locals that may be needed after a suspension point. Optimize frame size
later.

Managed fields inside a resumable frame use the same ownership metadata and
finalization helpers as ordinary managed locals, dynamic arrays, records, and
future containers.

## Surface Forms

### Async / Await

`async` routines return a `Task[T]` or `Future[T]`. `await expr` suspends until
the awaited task completes, then resumes with its result or exception.

Pascal-shaped example:

```pascal
async function Fetch(sock: TSocket): AnsiString;
begin
  Result := await ReadSocket(sock);
end;
```

Nil Python can expose the familiar spelling:

```python
async def fetch(sock: Socket) -> str:
    return await sock.read()
```

### Coroutines

Coroutines use the same resumable frame but expose explicit cooperative
transfer rather than task completion. The runtime contract should remain
small: create, resume, suspend, inspect completion, destroy.

### Yield / Generators

`yield value` is a specialized suspension point that publishes one value to an
enumerator consumer. A generator frame is naturally an implementation of the
container iteration protocol:

```text
MoveNext() -> Boolean
Current()  -> T
```

`yield from` and async generators are later syntax sugar once ordinary
generators and tasks are stable.

## Runtime Layers

Implement bottom-up:

1. `Task[T]` / `Future[T]` completion object and continuation queue.
2. Minimal event loop with timers and a wakeup queue.
3. Linux `epoll` backend for sockets, pipes, and UI-event integration.
4. Small worker pool for operations that remain blocking.
5. Manual continuation and manually written state-machine regressions.
6. Compiler lowering for Pascal `async` / `await`.
7. Compiler lowering for coroutine create/resume/suspend and `yield`.
8. Nil Python `async def`, `await`, and generator syntax over the same runtime.
9. Optional `io_uring` backend if it buys measurable value.

Linux filesystem I/O does not become generally non-blocking merely by using
`epoll`. DNS, legacy C APIs, CPU work, and some file operations still belong in
the worker pool. Async and threads are complementary.

## Threading Policy

- Event-loop callbacks run serially unless explicitly dispatched elsewhere.
- Containers remain unsynchronized by default.
- Cross-thread completion uses a thread-safe queue plus an event-loop wakeup.
- Exception state associated with a task belongs to that task, not shared
  process-global storage.
- Blocking wrappers may schedule work onto the worker pool and return a task.

This design benefits from the existing conditional atomic ownership operations
under `--threadsafe`, but it still requires a deliberate thread-safe exception
model and managed-frame finalization.

## Prerequisites

Before implementation:

- Finish string-capable `Variant`.
- Add the `TAnyBox` fallback tier and clarify its ownership rules.
- Land typed containers and their recursive finalization.
- Establish Nil Python module imports through a real full-chain target such as
  SQLite.
- Centralize the target-neutral allocator contract.
- Decide exception ownership for tasks and worker threads.

## Explicit Non-Goals For The First Slice

- Transparent conversion of every blocking function into async code.
- Preemptive scheduling.
- Distributed actors.
- Green-thread ABI compatibility with unrelated runtimes.
- Async generators, cancellation trees, structured concurrency, and
  `io_uring` in the first implementation.

## First Proof

The first proof should be intentionally small:

1. Create a timer future.
2. Manually resume a state machine after the timer fires.
3. Run two socket tasks concurrently on one thread.
4. Dispatch one blocking operation to the worker pool and deliver completion
   back to the event loop.
5. Verify managed strings and arrays captured in suspended frames finalize
   correctly.

Only then add language syntax.


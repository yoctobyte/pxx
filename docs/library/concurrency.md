---
title: Threads & parallelism
order: 55
---

# Threads & parallelism

The [coroutine scheduler](./async.md) gives cooperative concurrency on a single
OS thread. This page covers the other axis: **real OS threads** and
**data-parallel loops** that use every core. Both are libc-free: the runtime
talks to the kernel's thread primitives directly. When a program also links
libc (for example through a Pascal `external 'libc.so.6'` declaration),
threads are started through libc's `pthread_create` instead, so that each
thread has its own libc state and C code that allocates can run on several
threads at once.

> These are advanced surfaces. Multi-threaded code compiled without
> `--threadsafe` shares unmanaged refcounts and will corrupt managed strings and
> dynamic arrays under contention. Build threaded programs with `--threadsafe`.

## Targets

Threads work on x86-64, i386, aarch64 and arm32 Linux. On riscv32 and wasm32,
`--threadsafe` is refused at compile time, for example
`--threadsafe is available for x86-64, i386, aarch64 and arm32 only; it is
refused for riscv32.`

With pin v446 (compiler sha256 `ae3466a018d8`) and with the compiler at
`e072d579b0` (`ccd62c91f30e`), on 2026-09-28, every program on this page and
the `threadvar` example below compiled for each of the four targets and printed
the same output on each. Programs for the targets other than x86-64 were run
under QEMU user mode. The same happened for a C program using `__thread`, and
for two threads calling libc's `malloc` and `free` 400,000 times each
(`test/thread_glibc_malloc_two_threads.pas`, three runs per target).

Before v446, three things differed by target:

- i386 refused Pascal `threadvar`, and a C `__thread` variable was one copy
  shared by every thread (`7dc976a8cc`).
- A C `__thread` variable with an initialiser (`__thread int n = 7;`) started
  at 0 in every thread but the main one (`ce34aa72ef`).
- On i386, aarch64 and arm32, a thread in a program that links libc shared
  the main thread's libc state, and the compiler warned about it. Two
  threads allocating through libc at once could corrupt libc's heap and
  abort (`0ed2b7f6e1`). It does not happen on every run: three runs of the
  test above with v445 survived on each target.

## `TThread` — the `palthreadobj` unit

`TThread` is an FPC-style thread base class. Subclass it, override `Execute`, and
the body runs on its own OS thread.

```pascal
program worker;
{ compile with: ./pxx --threadsafe worker.pas worker }
uses palthread, palthreadobj;

type
  TAdder = class(TThread)
  public
    Sum: Int64;
  protected
    procedure Execute; override;
  end;

procedure TAdder.Execute;
var i: Integer;
begin
  Sum := 0;
  for i := 1 to 1000000 do
    Sum := Sum + i;            { runs on this thread's own OS thread }
end;

var t: TAdder;
begin
  t := TAdder.Create(False);   { False = start immediately }
  t.WaitFor;                   { block until Execute returns }
  writeln('sum = ', t.Sum);
  t.Free;                      { also Terminate+WaitFor if still running }
end.
```

To hand results back to the main thread safely, `Synchronize(m)` and `Queue(m)`
marshal a `TThreadMethod` onto it. Bind the method to a variable first
(`m := @Self.SomeMethod;`) — an inline `Synchronize(@Self.SomeMethod)` argument
is not parsed yet — and have the main thread call `CheckSynchronize` periodically
to run the queued work.

### Surface

| Member | Effect |
| --- | --- |
| `constructor Create(CreateSuspended: Boolean)` | Create the thread; `False` starts it at once, `True` waits for `Start`. |
| `procedure Start` | Begin a suspended thread. |
| `procedure Execute; virtual; abstract` | The thread body — override this. |
| `procedure WaitFor` | Block the caller until the thread finishes. |
| `procedure Terminate` | Set the cooperative `Terminated` flag; the body must observe it. |
| `procedure Synchronize(m)` / `procedure Queue(m)` | Run a method on the main thread — blocking / fire-and-forget. |
| `function ThreadID: Int64` | The OS thread id. |
| `property Terminated / Finished / Suspended` | Thread-state flags. |
| `property FreeOnTerminate` | Self-`Free` when `Execute` returns. |
| `property OnTerminate` | Method fired (on the main thread) when the thread ends. |

`Synchronize` and `Queue` deliver work to the main thread; the main thread runs
that work when it calls `CheckSynchronize` (or blocks in a runtime that pumps it).
`MainThreadID` and `CurrentThread` identify the running thread.

## `threadvar`: one copy per thread

A variable declared under `threadvar` has a separate copy in every thread. A
new thread's copy starts at zero, whatever the other threads hold.

```pascal
program tv;
{ compile with: ./pxx --threadsafe tv.pas tv }
uses palthread, palthreadobj;

threadvar
  Counter: Integer;           { one copy per thread }

type
  TWorker = class(TThread)
  public
    Id, Seen: Integer;
  protected
    procedure Execute; override;
  end;

procedure TWorker.Execute;
var i: Integer;
begin
  Counter := Id * 10;         { this thread's copy only }
  for i := 1 to 100000 do
    if Counter <> Id * 10 then Break;
  Seen := Counter;
end;

var a, b: TWorker;
begin
  Counter := 99;              { the main thread's copy }
  a := TWorker.Create(True); a.Id := 1;
  b := TWorker.Create(True); b.Id := 2;
  a.Start; b.Start;
  a.WaitFor; b.WaitFor;
  writeln('thread 1 saw ', a.Seen, ', thread 2 saw ', b.Seen, ', main has ', Counter);
  a.Free; b.Free;
end.
```

It prints `thread 1 saw 10, thread 2 saw 20, main has 99`. C's `__thread` is
the same: each thread gets its own copy, which starts at the variable's
initialiser.

## `parallel for` — the `palparallel` unit

`parallel for` is a language-level statement that fans a counted loop across a
libc-free worker pool. The compiler desugars it at parse time into a synthesised
worker procedure plus a pool dispatch — there is no closure allocation.

```pascal
program parsum;
{ compile with: ./pxx --threadsafe parsum.pas parsum }
uses palparallel;

const N = 100000;
var arr: array[0..N-1] of Integer;

procedure Run;
var i: Integer;
begin
  parallel for i := 0 to N-1 do
    arr[i] := i * 3;          { each iteration writes its own disjoint slot }
end;

begin
  Run;                        { must sit inside a routine, not the main body }
  writeln(arr[42]);
end.
```

Constraints in this version:

- Requires `--threadsafe` and `uses palparallel`.
- Must appear **inside a routine**, not directly in the main program body.
- The body may reference the loop variable, globals, and enclosing locals —
  scalars, strings, records, classes, and arrays alike — captured by reference
  through the frame. The one restriction is that the local's **type must be
  named**: an anonymous `var da: array of Integer` is refused, and the compiler
  says how to fix it —

  ```
  error: parallel for: capturing 'da' — its type is unnamed; declare it with
  a named type (e.g. `type TFoo = ...`) to capture it
  ```

  Give it a `type TDA = array of Integer;` and it captures like anything else.
- Iterations must be independent — the pool runs them concurrently and in no
  guaranteed order. Writing disjoint slots is safe; accumulating into one shared
  variable is a data race unless you guard it.

An optional policy clause tunes distribution (worker count, chunking); omit it
for the default that fans the range evenly across the pool.

### `reduction` and `private`

Two clauses sit between the range and `do`, and both exist because capture is by
reference:

```pascal
  parallel for i := 0 to N-1 reduction(+: total) private(scratch) do
  begin
    scratch := 0;
    while scratch < 3 do begin total := total + 1; scratch := scratch + 1; end;
  end;
```

- **`reduction(op: v, ...)`** — each worker accumulates into a private partial
  and folds it into `v` under a lock after the loop, so a shared accumulator is
  race-free. Ops are `+`, `or`, `xor`, `and`, `min`, `max` and `mul` (spelled as
  a word, because `(*` opens a comment).
- **`private(v, ...)`** — each worker gets its own copy of `v`, and nothing is
  written back. This is the clause for **scratch** storage: a temporary the body
  assigns on every iteration. Without it that temporary is one shared variable
  and the loop silently loses work.

Two things to know about `private`:

- It is **per worker**, not per iteration. Seed it in the body if the body needs
  a known starting value each time round, exactly as the example does.
- Each copy starts **zero / `False` / `nil` / empty**, where OpenMP's `private`
  leaves it uninitialised. Copying the enclosing value in (OpenMP's
  `firstprivate`) is not offered.

A variable may not appear in both clauses — `reduction` already gives it a
private, plus the combine.

Scalars and `AnsiString` may be private. Arrays, records and classes may not
yet; index a shared array by the loop variable instead, which needs no clause.

## Next

- [Coroutines & async](./async.md)
- [Standard library](./index.md)
- [Command-line reference](../reference/cli.md)

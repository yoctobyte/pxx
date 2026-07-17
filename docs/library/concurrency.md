---
title: Threads & parallelism
order: 55
---

# Threads & parallelism

The [coroutine scheduler](./async.md) gives cooperative concurrency on a single
OS thread. This page covers the other axis: **real OS threads** and
**data-parallel loops** that use every core. Both are libc-free — the runtime
talks to the kernel's thread primitives directly.

> These are advanced surfaces. Multi-threaded code compiled without
> `--threadsafe` shares unmanaged refcounts and will corrupt managed strings and
> dynamic arrays under contention. Build threaded programs with `--threadsafe`.

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
- The body may reference the loop variable, globals, and enclosing **scalar**
  locals (captured by reference through the frame). Capturing a record, class,
  array, or string local is not supported yet.
- Iterations must be independent — the pool runs them concurrently and in no
  guaranteed order. Writing disjoint slots is safe; accumulating into one shared
  variable is a data race unless you guard it.

An optional policy clause tunes distribution (worker count, chunking); omit it
for the default that fans the range evenly across the pool.

## Next

- [Coroutines & async](./async.md)
- [Standard library](./index.md)
- [Command-line reference](../reference/cli.md)

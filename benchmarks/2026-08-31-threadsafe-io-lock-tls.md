# The `--threadsafe` I/O lock stops paying a syscall per statement

`feature-a-io-lock-owner-from-tls-not-gettid`, landed 2026-08-31.

Box: this dev machine, load ~4 (Track T's watcher running). Program:
`bench/threadsafe_io_writeln.pas` — 400,000 `Writeln('x')` to `/dev/null`.
Method: interleaved A/B, seven rounds, **min of N** (means are meaningless
against a loaded box).

| build | compiler sha256 | min of 7 |
| --- | --- | --- |
| no `--threadsafe` | `8301ce20d5b9` | **0.48s** |
| `--threadsafe`, before | `13ff03adbf6d` | **0.71s** |
| `--threadsafe`, after | `8301ce20d5b9` | **0.49s** |

43% overhead → nothing measurable. `strace -c` on the same binary, before and
after:

| syscall | before | after |
| --- | --- | --- |
| `write` | 800000 | 800000 |
| `gettid` | **400000** | **1** |
| `getrlimit` | 0 | 1 |

One `gettid` per I/O statement was a third of all syscalls. It is now one per
*process*, cached in the thread's TLS block (`TLS_SLOT_TID`) and read behind the
stack-bounds check that makes reading it safe.

## What this does NOT measure

`Writeln` is still **two** `write(2)` calls, payload and newline, and that is
now the entire cost of this workload — 800,000 syscalls against the 400,001 the
lock used to add. Buffering console output would beat this whole change on this
shape, and it would help the unlocked build too. Separate ticket; the ratio
above is what remains after the lock is free.

## What is still on the slow path, deliberately

**Cloned threads.** The clone stub knows the top of the child's stack and not
the bottom — only whoever allocated the stack knows that — so their bounds stay
zero, which is the fail-safe case: they miss the fast path and pay `gettid`,
exactly as before this change. **Foreign threads** (glibc `pthread_create`) also
miss, and that is not a limitation but the entire point: they read a block they
inherited and must not be believed.

So the measured win is the **main thread's**, which is where a single-threaded
`--threadsafe` program does all of its I/O.

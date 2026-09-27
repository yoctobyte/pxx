---
slug: bug-s-espide-auto-never-exits-after-build-flash
track: S
type: bug
prio: 60
status: open
owner: frankZ
created: 2026-09-27
summary: "espide wedges in the monitor phase and never returns: measured 2h49m on a monitor asked for 8 s, and 2835 s on one asked for 6 s. The main thread sits in state D with wchan=anon_pipe_read, and the fd table (read from inside the process's own group -- setgid `sg dialout` clears dumpable, so an outside reader gets EPERM) contains exactly ONE pipe, fd 13, the read end of the monitor child's stdout; the `cat` child is alive in state S with the port idle, so that pipe is EMPTY. So espide blocks in read() on an empty pipe whose writer is alive. NOT YET EXPLAINED: espide's only reader is StreamPoll (runner.pas:133), it is called with timeoutMs=0 (main.pas:819), PalPoll is a ppoll with a {0,0} timespec that returns 0 on an empty pipe, and PalRead is a single raw read() that does not loop -- so by inspection StreamPoll cannot block, and the measurement says it does. Inspection has been wrong twice here; trust the measurement. Two REAL defects were found and fixed alongside, and NEITHER fixes this: (1) AddLog assigned the whole buffer to the GtkTextView and called CountLines per arriving chunk, O(LOG_CAP) against a 64 KB-per-tick drain cap -- a genuine performance defect, and the reason the stdout log froze too, because the `write` sat last behind the GTK work; (2) OnTick measured the monitor window by counting timer ticks rather than elapsed clock time. After both fixes the hang reproduces unchanged."
---

# espide's monitor wedges: the main thread blocks in read() on an empty pipe

> **Revision history. I have been wrong about this ticket twice, in opposite
> directions, and the record of that is worth more than a clean-looking ticket.**
>
> 1. **Filed** as "--auto never exits after Build+Flash", on three rc=124 runs.
> 2. **Corrected, wrongly**, to "it does exit; the real defect is that the
>    monitor window is counted in ticks". Based on one clean 6 s run and a
>    diagnostic that found the process alive. A diagnostic that finds a process
>    alive has not found it making progress.
> 3. **Corrected again**, to "AddLog's per-chunk pane rewrite is the cause".
>    That was a real defect, found by real measurement, and it is not this bug.
>    I promoted the first plausible mechanism I could measure to "root cause"
>    without testing that removing it removed the hang.
> 4. **This revision.** With both fixes in, a monitor asked for 8 s ran
>    **2h49m** and was still wedged when I killed it. The hang is real,
>    reproducible, and **not yet explained**.
>
> The recurring error is mine and it is the same one each time: I let a
> mechanism I had confirmed to exist stand in for a cause I had not confirmed.
> The discipline that was missing is the cheapest one available — after a fix,
> re-run the failing case before writing "fixed".

- **Type:** bug — Track S
- **Status:** OPEN — two contributing defects fixed, the hang itself unexplained
- **Priority:** raised 40 → 60. The GUI Monitor button feeds the same path, and
  the owner will press it.

## What happens

`espide --auto --port <by-id> examples/esp32/hello-esp32 8` on a live classic
ESP32 over the CP2102 bridge: Detect answers `ESP32 rev v3.1`, Build+Flash
completes and the board runs the program, `StartMonitor` logs `--- serial
<port> (115200) ---`, and then espide never returns.

Measured, most recent run, with both fixes below already in the binary:

- **2h49m08s** elapsed on a monitor asked for **8 s**, still wedged when killed.
- The log froze at the `--- serial ... ---` line and never advanced —
  **9957 s** without a byte, while `write` to stdout is now the FIRST thing
  `AddLog` does. So `AddLog` was never entered: the wedge is upstream of it.
- espide main thread `state=D` (uninterruptible), `wchan=anon_pipe_read`.
- The `cat` child is alive, `state=S`, port idle — so the pipe is **empty**.
- It survives SIGTERM (D state); `kill -9` is needed.

## The evidence that pins it, and how to collect it

The fd table is the datum this ticket asked for through two revisions and did
not have. Collecting it needs one non-obvious step: espide is launched under
`sg dialout`, which is **setgid**, and that clears the process's dumpable flag —
so `/proc/<pid>/fd` and `/proc/<pid>/syscall` give **EPERM to an outside
reader**, including to the same user. Read them from inside the same group:

```sh
sg dialout -c 'pid=<pid>; cat /proc/$pid/wchan; ls -l /proc/$pid/fd/'
```

That yields exactly one pipe in the whole table:

```
lr-x------ 13 -> pipe:[290414493]      # read end of the monitor child's stdout
                                       # fd 14 absent: the write end is correctly
                                       # closed in the parent
```

plus `wchan=anon_pipe_read`. One pipe, empty, live writer, main thread blocked
reading it. `/proc/<pid>/syscall` stays EPERM even inside the group, so the fd
number comes from the table being a singleton rather than from the syscall args.

## Why this should be impossible, which is the open question

espide's only reader of that fd is `StreamPoll` (`apps/ide/garin/runner.pas:133`):

- It is called as `StreamPoll(Proc, 0)` — timeout **0** (`apps/ide/esp/main.pas:819`).
- `PalPoll` → `PalBackendPoll` (posix) builds a `{0, 0}` timespec and calls
  `ppoll`, returning 0 on timeout and the revents mask otherwise. On an empty
  pipe with a live writer `ppoll` returns 0, so `StreamPoll` takes `if ev <= 0
  then Break` and never reads.
- `PalRead` → `PalBackendRead` is a **single** raw `read()` syscall. It does not
  loop to fill the buffer, so a partial read cannot stall waiting for the rest.
- A revents of `POLL_HUP` or `POLL_ERR` alone would reach `PalRead`, but on a
  pipe those make `read()` return 0 or -errno, not block.

So by inspection `StreamPoll` cannot block, and the measurement says something
in this process does. **One of those two is wrong and it is not the
measurement.** Inspection has already been wrong twice on this ticket.

## Next step, and the instrument note that goes with it

Trace espide's own syscalls **without `-f`**. `strace -f` follows the whole
cmake/ninja tree that Build+Flash spawns — thousands of processes — and that is
the overhead that made two earlier attempts useless (the monitor phase was never
reached inside the wait). espide's own threads are what matter and `cat` is a
separate process, so `-f` buys nothing here and costs the run:

```sh
strace -tt -e trace=ppoll,read,close -o tr.out ./apps/ide/esp/espide --auto ...
```

`ptrace_scope=1` on plexus allows tracing a direct child, which this is.

## Hypotheses and their current standing

1. **Harness timeout too short.** REFUTED: warm re-run with `timeout 900`
   behaved identically, and the latest run wedged for 2h49m unbounded.
2. **`StreamPoll(Proc, 0)` blocks on a silent child.** Bochan row `poll with
   timeout 0 returns at once` passes for a live silent child — so it does not
   block *in that shape*. The shape that wedges is a child that has already
   delivered data. Not refuted, narrowed; this is now the prime suspect.
3. **`ChildDone` clears `Mode` after the `case`.** REFUTED: `m := Mode; Mode :=
   mIdle;` happens before the `case`.
4. **`Ticker` enabled too late.** REFUTED: enabled before `StartBuild`.
5. **`StreamPoll` reads an fd `poll` did not report readable.** **REOPENED.**
   I marked this refuted by arguing from `PalBackendPoll`'s contract. The fd-13
   evidence says a blocking read is happening on exactly this path. The
   argument was sound and the conclusion is contradicted by measurement, which
   means an assumption inside it is false — most likely about what `ppoll`
   returns in revents, or about the value `POLL_IN` actually carries here.
6. **`RunCapture`'s read-to-EOF loop.** REFUTED, re-verified: its only call
   sites are in eliah (`apps/ide/eliah/main.pas:447,475`), not espide.
7. **Carrier-detect stall on the port.** REFUTED: `clocal` set, and a bare
   `timeout 3 cat <port>` returns 0 bytes rather than blocking in `open`.
8. **SIGTERM discarding a flushed tail.** REFUTED: sampled with `stdbuf -o0`.
9. **`AddLog`'s per-chunk pane rewrite.** A real defect, fixed, **not the
   cause**: the hang reproduces with the fix in, and the frozen stdout log now
   proves `AddLog` is not even reached.

## The two defects that WERE fixed here

Both are real, both are worth keeping, neither fixes the hang. They are landed
under this ticket rather than a new one because they were found by its
investigation and the ticket must not imply they cured it.

1. **`AddLog` rewrote the whole log pane for every arriving chunk.** It set
   `Log.Text` (up to `LOG_CAP` = 32 KB) and called `CountLines` over the same
   buffer per chunk, while `StreamPoll`'s drain cap delivers up to 16 × 4096 =
   **64 KB per 100 ms tick**. `LOG_CAP`'s own comment already records this
   failure mode on the S3 — "the window fell minutes behind its own child" —
   and mitigated it by capping the buffer; capping cut the constant and left the
   cost O(cap) *per chunk*. Now coalesced behind `FlushLog` gated on
   `LOG_FLUSH_MS` = 250, with a catch-up flush in `OnTick` and a final one in
   `ChildDone`.
2. **The stdout `write` was the LAST statement in `AddLog`**, behind the GTK
   work. That is why the log file froze in lockstep with the pane and a live
   process was indistinguishable from a dead one — it cost me two wrong
   diagnoses. It is now first, with an explicit `Flush(Output)`: the record a
   headless run leaves must not queue behind a widget.
3. **`OnTick` counted timer ticks, not elapsed time.** `AutoTicks * TICK_MS`
   assumed every tick arrived on its 100 ms schedule, so `--auto <n>` meant n
   tick-periods. Now `GetTickCount64 - AutoMonT0`, and the stop line reports
   `N s (M ticks; K ms elapsed)` so a future overrun is visible rather than
   inferred.

## Notes

- The Detect single-port fix found alongside this landed first and separately
  (80847982ad): until it was in, Detect reset boards the user had not chosen.
- `runner.pas` documents that `StreamPoll` "never blocks longer than
  timeoutMs". Whatever the mechanism turns out to be, that contract is being
  violated. The interface also lacks any bound on how much one call may return;
  64 KB per 100 ms tick is more than a GTK-driven caller can absorb.

---
slug: bug-s-espide-auto-never-exits-after-build-flash
track: S
type: bug
prio: 60
status: open
owner: frankZ
created: 2026-09-27
summary: "espide's monitor never returns: reproduced repeatedly, 45 s to 4h36m on a monitor asked for 8 s. MEASURED, 2026-09-28, on the wedged process: main thread state D, utime frozen at 827 and stime at 42 across 20 s (so it is NOT spinning), syscr frozen at 435119 across 5 s (so no syscall is completing -- it is blocked inside one), wchan=anon_pipe_read, exactly ONE pipe in the fd table (fd 17, inode matching the `cat` child's fd 1), and that fd's live flags are 02004000 = O_CLOEXEC|O_NONBLOCK -- so O_NONBLOCK IS SET and a read cannot sleep waiting for data. The GLib timerfd reads it_value (0,0) it_interval (0,0) ticks 0, which is what the loop looks like while stuck INSIDE a dispatch rather than waiting for the next tick. So: blocked inside an OnTick dispatch, in the pipe read path, on a non-blocking fd, consuming no CPU. The only mechanism left that fits every number is contention on the pipe's own mutex rather than on data (a non-blocking reader still sleeps for pipe->mutex, in D, inside anon_pipe_read, burning nothing); NOT established. Four real defects were found and fixed on this path and NONE of them is the cause: the per-chunk GtkTextView rewrite, the stdout write sitting last behind it, the monitor window counted in ticks instead of clock time, and raw serial bytes fed to a UTF-8 widget. IMPORTANT for whoever continues: wchan=anon_pipe_read is NOT evidence of a blocking read here, and three of my hypotheses were built on reading it that way."
---

# espide's monitor wedges: blocked in the pipe read path on a NON-BLOCKING fd

- **Type:** bug — Track S
- **Status:** OPEN. Four contributing defects fixed; the hang itself unexplained.
- **Priority:** 60. The GUI Monitor button feeds the same path and the owner will
  press it.

> **I have been wrong about this four times, and the pattern matters more than
> any single wrong answer: each time I promoted a mechanism I had confirmed to
> EXIST into the cause, without testing that removing it removed the hang.**
>
> 1. Filed as "--auto never exits", on three rc=124 runs.
> 2. "It does exit; the window is counted in ticks." Wrong — from one clean run
>    and a diagnostic that found the process alive. Finding a process alive is
>    not finding it making progress.
> 3. "AddLog's per-chunk pane rewrite is the cause." A real defect, real
>    measurements, not the cause: the hang reproduced with it fixed.
> 4. "It blocks in read() because poll and read disagree." Built on
>    `wchan=anon_pipe_read`. The fd is O_NONBLOCK, measured live, so that read
>    cannot be waiting for data at all.
>
> The cheapest missing discipline each time: re-run the failing case before
> writing "fixed".

## Reproduction

`espide --auto --port <by-id> examples/esp32/hello-esp32 8` on a live classic
ESP32 over the CP2102. Detect answers `ESP32 rev v3.1`, Build+Flash completes,
`StartMonitor` logs `--- serial <port> (115200) ---`, and espide never returns.
Observed durations for an 8 s monitor: 45 s (cut short by the probe), 223 s,
2835 s, 4h36m. It survives SIGTERM; `kill -9` is needed.

Reproduces about half the time — not because the bug is intermittent, but
because the flash fails on roughly half the runs and the monitor is then never
reached. That flash failure is a separate matter: since 2026-09-28
`tools/esp_flash.sh` prints esptool's own reason on a failing write, which it
previously discarded.

## The measurements that matter

All taken on the wedged process. espide runs under setgid `sg dialout`, which
clears the dumpable flag, so `/proc/<pid>/fd` and `/proc/<pid>/fdinfo` give
**EPERM to an outside reader** — take them with `sg dialout -c`.

| what | value | what it rules out |
|---|---|---|
| main thread state | `D` | — |
| `utime`/`stime` over 20 s | frozen at 827 / 42 | **not spinning** |
| `syscr` over 5 s | frozen at 435119 | **no syscall completing**; blocked inside one |
| `wchan` | `anon_pipe_read` | — (see the warning below) |
| pipes in the fd table | exactly one, fd 17 | no second, hidden pipe |
| fd 17 inode vs `cat` fd 1 | identical (`316545205`) | it IS the monitor child's pipe |
| **fd 17 live flags** | **`02004000` = O_CLOEXEC\|O_NONBLOCK** | **a read cannot wait for data** |
| GLib timerfd (fd 21) | `it_value (0,0)`, `it_interval (0,0)`, `ticks 0` | not waiting for a tick — stuck inside a dispatch |
| `cat` child | alive, state `S`, `wait_woken` | writer alive, pipe empty |
| other threads | `futex_do_wait`, `poll_schedule_timeout`, `ep_poll` | ordinary |

### The warning, because it cost me three hypotheses

**`wchan=anon_pipe_read` is not evidence of a read blocking for data.** With
`O_NONBLOCK` confirmed on the live fd, the only way to sleep in that function
consuming no CPU is to wait for something other than data — the pipe's own
mutex being the obvious candidate. Do not re-derive "poll and read disagree"
from this wchan; that was hypothesis 4 and the flags refute it.

## What the fix has to satisfy

Zero CPU, no syscall completing, one non-blocking pipe, and a GLib loop stuck
mid-dispatch. Whatever the mechanism, espide must not be able to reach a state
where a timer-driven callback does not return.

## Next instrument, and why the obvious ones failed

A stack is the one thing missing. Every attempt so far failed for a reason worth
recording rather than repeating:

- **`gdb -p <pid>`**: refused. `ptrace_scope=1` on plexus allows attaching only
  to a direct child, and a probe script's gdb is not espide's parent
  (`ptrace: Inappropriate ioctl for device`).
- **`strace -f`**: useless. It follows the whole cmake/ninja tree that
  Build+Flash spawns, and the monitor phase is never reached inside the wait.
  Plain `strace` (no `-f`) is cheap and did work — it showed `PalPoll` returning
  revents correctly during the build phase (`ppoll([{fd=17,events=POLLIN}],
  {0,0}) = 1 ([{fd=17,revents=POLLIN}])` → `read = 99` → `= 0 (Timeout)` →
  break), which is how hypothesis 4's premise was first weakened.
- **`/proc/<pid>/syscall`**: EPERM even inside the group, so the blocked
  syscall's own arguments are not available this way.

So: **run espide as gdb's own child** — `gdb -batch -ex run -ex 'thread apply
all bt' --args ./apps/ide/esp/espide --auto ...` with a `timeout -s INT` long
enough to land past the ~115 s build (`run` returns when SIGINT stops the
inferior, then the next `-ex` prints the stack). Note pxx emits executables with
**no section header**, so symbolisation may need `apps/ide/esp/espide.map`.

## Hypotheses and their standing

1. Harness timeout too short — REFUTED (unbounded 4h36m run).
2. `StreamPoll(Proc, 0)` blocks on a silent child — bochan proves it returns at
   once for a live silent child; narrowed, not the shape that wedges.
3. `ChildDone` clears `Mode` after the `case` — REFUTED, it is before.
4. `Ticker` enabled too late — REFUTED, before `StartBuild`.
5. `StreamPoll` reads an fd `poll` did not report readable — **REFUTED by the
   fd flags**, after I wrongly refuted it by argument, then wrongly reopened it.
6. `RunCapture`'s read-to-EOF loop — REFUTED, re-verified: eliah-only
   (`apps/ide/eliah/main.pas:447,475`). `espproj` has no capture at all and
   `OnTick` calls nothing else, so there is no other pipe reader on the path.
7. Carrier-detect stall — REFUTED (`clocal` set; a bare `timeout 3 cat <port>`
   returns 0 bytes rather than blocking in `open`).
8. SIGTERM discarding a flushed tail — REFUTED (sampled with `stdbuf -o0`).
9. `AddLog`'s per-chunk pane rewrite — real, fixed, NOT the cause.
10. Raw serial bytes tripping `g_utf8_validate` — real, fixed, NOT the cause:
    with the sanitiser in, Gtk-CRITICALs are zero and the hang is unchanged.
11. The stop/drain path killing the wrong pid and draining to EOF — REFUTED for
    this wedge: fd 17 is **still open**, and `StreamReap` closes it before
    `PalWait4`, so the stop path was never entered. (It remains worth a look as
    a separate question: `StreamStop` signals `p.Pid`, the `bash -c` wrapper,
    while `sg dialout` sits between it and `cat`. Here `cat` was a direct child,
    so the execs did collapse.)
12. **Pipe-mutex contention** — the only mechanism left that fits every number.
    NOT established.

## The four defects fixed under this ticket

Landed here rather than under a new slug because this investigation found them,
and recorded as fixes rather than cures so the shas do not read as a cure.
`0cc5b6c12f`, `e3818c0112`.

1. `AddLog` set `Log.Text` (full GtkTextView rewrite, `LOG_CAP` 32 KB) and
   `CountLines` over the same buffer per arriving chunk, against a 64 KB-per-tick
   drain cap. `LOG_CAP`'s own comment already recorded this wedge on the S3 and
   mitigated it by capping — which cut the constant and left the cost O(cap) per
   chunk. Now coalesced behind `FlushLog` on a 250 ms gate.
2. The stdout `write` was the LAST statement in `AddLog`, behind the GTK work, so
   a headless run's log froze in lockstep with the pane and a live process looked
   dead. Now first, with `Flush(Output)`.
3. `OnTick` measured the window as `AutoTicks * TICK_MS`. Now elapsed
   `GetTickCount64`, and the stop line prints `N s (M ticks; K ms elapsed)`.
4. The pane was fed raw serial bytes; GTK rejected whole chunks with
   `gtk_text_buffer_emit_insert: assertion 'g_utf8_validate' failed`, and a NUL
   truncated the C string. `SanitizeUtf8ForText` lives in `garin/runner` so
   bochan can test it (9 rows).

Also on this path: `O_NONBLOCK` on the child's stdout with `EAGAIN` handled
separately from EOF (`n <= 0` reaps the child, so "no data yet" must not read as
"child finished"). The guard is a **direct** read, because `StreamPoll` asks poll
first and so never reaches the read on a quiet child — it cannot witness the
property. Removing the `EAGAIN` branch as a mutation left all 306 rows passing;
removing the `fcntl` fails the new row with `got=0`.

## Notes

- The Detect single-port fix found alongside this landed first and separately
  (`80847982ad`): until it was in, Detect reset boards the user had not chosen.
- `runner.pas` documents that `StreamPoll` "never blocks longer than timeoutMs".
  Something on this path violates that. The interface also lacks any bound on how
  much one call may return; 64 KB per 100 ms tick is more than a GTK-driven
  caller can absorb.

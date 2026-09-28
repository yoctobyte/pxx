---
slug: bug-s-espide-auto-never-exits-after-build-flash
track: S
type: bug
prio: 60
status: fixed
owner: frankZ
created: 2026-09-27
summary: "SOLVED 2026-09-28, root cause proven and fixed. espide's monitor ran `cat <port>`; /bin/cat on plexus is uutils coreutils 0.8.0, which moves tty -> pipe with splice(tty, NULL, pipe, NULL, 1MB, 0). splice() into a pipe takes pipe->mutex and HOLDS IT while waiting for source bytes, so a quiet board parks cat inside splice holding the lock. pipe_read() takes that same mutex BEFORE it checks O_NONBLOCK, so espide's non-blocking fd bought nothing: it slept in state D (uninterruptible -- SIGTERM and SIGKILL do not end it) with zero CPU until the board next emitted a byte, which is why an 8 s monitor was observed hanging 45 s, 223 s, 2835 s and 4h36m. The kernel said so independently in dmesg: 'INFO: task espide is blocked on a mutex likely owned by task cat'. FIX: the monitor child is now `dd if=<port> bs=512 status=none`, which uses read/write and never splices (measured: 0 splice calls on both the uutils and GNU flavours). Proven by a 15-second board-free A/B on a pty: with cat, 0 ticks of progress in 12 s and state D, unreapable by SIGKILL; with dd, 60 ticks and state S. THE INVARIANT for whoever edits StartMonitor next: the monitor child must not splice into our pipe. There is no defence on the reader's side -- a D-state read cannot be interrupted from userspace -- so it has to be avoided in the child."
---

# espide's monitor wedged: a child holding pipe->mutex across a splice() wait

- **Type:** bug — Track S
- **Status:** FIXED. Root cause proven; fix verified board-free and on the board.
- **Priority:** 60. The GUI Monitor button feeds the same path.

## The cause, in one paragraph

`StartMonitor` spawned `cat <port>` and read its stdout pipe from the GTK tick.
`/bin/cat` on plexus is **uutils coreutils 0.8.0** (`/usr/lib/cargo/bin/coreutils/cat`),
not GNU, and it moves tty→pipe with `splice(3, NULL, 1, NULL, 1048576, 0)`.
`splice()` into a pipe acquires `pipe->mutex` and **holds it while it waits for
bytes from the source**. So whenever the board went quiet, `cat` sat inside
`splice` holding the lock (state `S`, wchan `wait_woken` — the `n_tty_read`
wait). Meanwhile `pipe_read()` acquires that same mutex **before** it looks at
`O_NONBLOCK`, so espide's carefully non-blocking fd bought nothing: `poll`
reported `POLLIN` for bytes an earlier splice had already delivered, and the
following `read()` slept in **state D** — uninterruptible, so neither SIGTERM
nor SIGKILL ended it — with zero CPU, until the board next said something.

That last detail is the whole distribution of symptoms: **the hang lasts exactly
as long as the board stays quiet.** Hence an 8 s monitor observed at 45 s, 223 s,
2835 s and 4h36m, the 4h36m being a board sitting in a panic loop that had gone
silent.

## The fix

`apps/ide/esp/main.pas`, `StartMonitor`: the child is now

    dd if=<port> bs=512 status=none

`dd` uses `read`/`write` and never splices — measured, 0 `splice` calls, on both
the uutils and the GNU flavour — so it holds `pipe->mutex` only across a memcpy.

Also fixed in `apps/ide/garin/runner.pas`: `StreamStop` called
`PalKill(p.Pid, SIG_TERM)` unguarded, and `StreamReap` leaves `Pid` at 0, so a
second `StreamStop` on a reaped record sent SIGTERM to **pid 0 — our own process
group**. Now guarded by `if p.Pid > 0`.

**The invariant, for whoever edits `StartMonitor` next: the monitor child must
not splice into our pipe.** There is no defence available on the reader's side.
A `read()` blocked on `pipe->mutex` is in `D`; no signal reaches it, no timeout
applies, and `O_NONBLOCK` is checked too late to matter. It has to be avoided in
the choice of child.

## Proof, and it needs no board

15 seconds, no board, no GTK, no ESP-IDF: open a pty, run the espide reader shape
(`poll` then `read` on the child's pipe from a 200 ms tick), have the child read
the pty, send **one** burst, then stay quiet. Bytes must be left in the pipe when
the source goes quiet — that is what makes `poll` say `POLLIN` while the child is
already back inside `splice`.

| child | progress in 12 s | state | reapable |
|---|---|---|---|
| `exec cat <pty>` | **0 ticks** | **D** | no — survives SIGKILL |
| `exec dd if=<pty> bs=512 status=none` | 60 ticks | `S` | yes |

An earlier two-burst version of the same run caught the mechanism in miniature
rather than permanently: `worstTickMs=500` with `cat` against `0` with `dd` —
the stall ended the instant the pty spoke again, which is the same clock the
board wedges ran on.

The reader used was a ~90-line program over `garin/runner`'s real `StreamStart`
/`StreamPoll`, so it exercised the shipped code path, not a model of it.

## What guards this, and what cannot

The invariant now lives in code rather than in a comment:
`EspMonitorCmd(port, useSg)` in `apps/ide/garin/espproj.pas` builds the monitor
command, `StartMonitor` calls it, and bochan checks it without a board or a
display (7 rows: reads with `dd`, does **not** read with `cat`, sets the line raw
first, `exec`s so the pid we signal is the reader itself, quotes a
shell-hostile port for both `stty -F` and `dd if=`, and goes through `sg` when
asked). Mutating `dd` back to `cat` fails those rows.

**Two things that do NOT guard it, both measured rather than assumed:**

- **The GUI smoke test cannot catch this.** A new `--gui-monitor-smoke` mode
  presses the real `OnMonitor` and `OnStop` handlers under Xvfb and asserts
  control came back; it passes on the fix. But with `cat` put back it **also
  passes** — because the wedge needs bytes sitting unread in the pipe when the
  source falls silent, and a quiet board means `poll` reports nothing ready, so
  the deadlocking read is never reached. The mode is worth having (it is the only
  thing that drives the Stop button at all, which `--gui-smoke` never did, since
  that only opens, paints and quits) but it is **not** a regression guard for
  this bug, and the comment on it says so.
- **A FIFO does not reproduce it; the source must be a tty.** `cat <fifo>` with
  one burst then silence gave 50 ticks of progress and state `S`. So the
  reproducer cannot be written in shell alone — it needs a pty — which is why the
  gate guards the command string instead of re-deriving the deadlock.

So the regression that is actually guarded is the one that would actually happen:
this line being edited back to a splicing reader.

## How it was finally localised, after five instruments failed

Every **external** instrument failed, each for a reason worth not repeating:

- `objdump -d` — nothing: pxx emits executables with **no section header**.
- `strace -f` — never reaches the monitor; it follows the whole cmake/ninja tree
  that Build+Flash spawns. Plain `strace` (no `-f`) does work.
- `gdb -p <pid>` — refused: `ptrace_scope=1` allows only a direct child.
- gdb as espide's own **parent** — attaches, symbolises nothing (`?? ()` every
  frame), and did not reach the monitor inside 260 s.
- `/proc/<pid>/syscall` and `/stack` — EPERM even inside the group (they need
  PTRACE_MODE_ATTACH). Note `sg` is setgid, which clears the dumpable flag, so
  `/proc/<pid>/fd` and `/fdinfo` also need reading **via** `sg dialout -c`.
- `wchan` — said `anon_pipe_read` for a fd that is provably `O_NONBLOCK`, which
  sent three hypotheses down the wrong path. It is the *frame*, not the reason.

So the subject was made to report its own position: `PXX_IDE_TRACE=1`
(`garin/runner`, commit `45f56ed278`) writes one token per `StreamPoll` step to
stderr, flushed per token, so the **last token before a freeze is the step that
did not return**. It printed, on the board and later on a bare pty:

    [poll fd=17 t=0][ev=0]   x many   <- nothing ready, break, correct
    [poll fd=17 t=0][ev=1]            <- poll reports POLLIN: data IS available
    [read]                            <- entered PalRead, never returned

**The instrument that should have been reached for first, and cost nothing:
`dmesg`.** A task in `D` for 120 s trips the kernel's hung-task detector, and it
had already written the answer, on two separate days and under two binaries:

    INFO: task espide:1805908 blocked for more than 122 seconds.
    INFO: task espide:1805908 is blocked on a mutex likely owned by task cat:1821590.

## Wrong turns, kept because the pattern repeated

Four times a mechanism confirmed to **exist** was promoted to the cause without
re-running the failing case:

1. "--auto never exits" — filed on three rc=124 runs.
2. "It does exit; the window is counted in ticks." Finding a process alive is not
   finding it making progress.
3. "`AddLog`'s per-chunk pane rewrite is the cause." Real defect, real
   measurements, not the cause — the hang reproduced with it fixed.
4. "poll and read disagree." Built on `wchan=anon_pipe_read`, refuted by the fd
   flags.

Two measured dead ends from the final stretch, recorded so they are not retried:

- **Re-asserting `O_NONBLOCK` immediately before the read changed nothing** —
  as it must not, since the mutex is taken first. Reverted rather than kept.
- **A full pipe is not the trigger.** `yes` and `dd bs=1M` writers with a reader
  stalled 3 s per tick drain cleanly (worst tick 5 ms). Nor are `sg dialout` in
  the chain, a pty source, or prior children on the same record; all four were
  tested board-free and none wedges. Only a *splicing* child does.
- One instrument lied again and was caught by a positive control:
  `PalNanosleep(0, 3000*1000000)` does not sleep — `nsec` must be < 1e9, so it
  returned EINVAL and eight "3 s" ticks took 6 ms total. Split into sec+nsec, a
  2-tick 1000 ms run measured `elapsed=2002`, and only then were the results
  trusted.

## Four real defects fixed along the way, none of them the cause

`0cc5b6c12f`, `e3818c0112`. Kept under this slug because this hunt found them.

1. `AddLog` set `Log.Text` (a full GtkTextView rewrite, `LOG_CAP` 32 KB) plus
   `CountLines` over the same buffer per arriving chunk, against a 64 KB-per-tick
   drain cap. `LOG_CAP`'s own comment already recorded this wedging the S3 and
   mitigated it by capping — which cut the constant and left the cost O(cap) per
   chunk. Now coalesced behind `FlushLog` on a 250 ms gate.
2. The stdout `write` was the **last** statement in `AddLog`, behind the GTK
   work, so a headless run's log froze in lockstep with the pane and a live
   process looked dead. Now first, with `Flush(Output)`.
3. `OnTick` measured the monitor window as `AutoTicks * TICK_MS`. Now elapsed
   `GetTickCount64`, and the stop line prints `N s (M ticks; K ms elapsed)`.
4. The pane was fed raw serial bytes; GTK rejected whole chunks with
   `gtk_text_buffer_emit_insert: assertion 'g_utf8_validate' failed`, and a NUL
   truncated the C string. `SanitizeUtf8ForText` moved into `garin/runner` so
   bochan can test it (9 rows).

`O_NONBLOCK` on the child's stdout with `EAGAIN` handled separately from EOF also
landed here (`n <= 0` reaps the child, so "no data yet" must not read as "child
finished"). Its bochan guard is a **direct** read, because `StreamPoll` asks poll
first and so never reaches the read on a quiet child — it cannot witness the
property. Removing the `EAGAIN` branch as a mutation left all 306 rows passing;
removing the `fcntl` fails the new row with `got=0`.

## Notes

- The Detect single-port fix found alongside this landed first and separately
  (`80847982ad`): until it was in, Detect reset boards the user had not chosen.
- `runner.pas` documents that `StreamPoll` "never blocks longer than timeoutMs".
  That promise cannot be kept against a splicing child, and the unit now says so
  where the `fcntl` is set.
- espide's line 752 was the **only** `cat <port>` in the tree;
  `tools/esp_serial_capture.py` opens the port with pyserial and is unaffected,
  so the fleet's long soaks were never exposed to this.
- Roughly half of all runs never reach the monitor at all because the flash
  fails; that is separate, and since 2026-09-28 `tools/esp_flash.sh` prints
  esptool's own reason on a failing write instead of discarding it.

## Closing note: reach for dmesg first

The cause was written in the kernel log, in plain words, on two separate days and
under two different binaries, before any of this investigation happened:

    INFO: task espide:1805908 is blocked on a mutex likely owned by task cat:1821590.

Any task stuck in `D` for 120 s trips the hung-task detector, and a hang that
"survives SIGTERM" is exactly that case. `dmesg` costs one command and needs no
privilege, no ptrace and no rebuild. It was reached for **sixth**, after
`objdump`, `strace -f`, `gdb -p`, gdb-as-parent and `wchan` — five instruments
that between them cost days and produced three wrong hypotheses, one of them
built on `wchan` naming a frame and being read as naming a reason.

**So: when a process is wedged and unkillable, read `dmesg` before building an
instrument.** The corollary held too — the subject's own trace
(`PXX_IDE_TRACE=1`) beat every external debugger on this target, because pxx
executables carry no section header and `ptrace_scope=1` blocks attaching to
anything that is not your own child.

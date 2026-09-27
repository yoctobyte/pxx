---
slug: bug-s-espide-auto-never-exits-after-build-flash
track: S
type: bug
prio: 40
status: backlog
owner: ""
created: 2026-09-27
blocked-by: []
summary: "espide --auto never terminates after a successful Build+Flash: it prints the monitor's opening line and then sits in D state with wchan=anon_pipe_read, ignoring AutoSecs. Measured on a live ESP32 (CP2102) with AutoSecs=8: still running 15 minutes later, killed by the harness timeout, rc=124. Detect and Build+Flash themselves work and the board runs the program, so this is the monitor phase only. NOT introduced by the Detect single-port fix (610c696fd7 onward) -- it is on the path the GUI Monitor button uses too. Five hypotheses refuted by measurement, listed below, so they need not be redone."
---

# espide --auto never exits after Build+Flash (monitor phase hangs)

- **Type:** bug — Track S
- **Status:** backlog
- **Opened:** 2026-09-27, found while exercising the IDE's board path on silicon

## What happens

`espide --auto --port <by-id> examples/esp32/hello-esp32 8` on a live classic
ESP32 over the CP2102 bridge:

1. Detect asks the one chosen port and answers `ESP32 rev v3.1` — correct.
2. Build+Flash completes: `Build+Flash: done, the board is running it.` The
   board really is running it (the `PXX hello ...` lines appear during the
   flash capture).
3. `StartMonitor` logs `--- serial <port> (115200) ---`.
4. Nothing further, ever. `AutoSecs` is ignored, `--- monitor stopped after N s
   ---` never prints, `AutoFinish` is never reached, `ESPIDE-AUTO-COMPLETE`
   never prints. Measured: `AutoSecs=8`, process still alive 15 minutes later
   (20:02:21 → 20:17:21), killed by the harness, rc=124.

So the exit status of a headless run is the harness's timeout, which is not a
verdict. A batch caller cannot tell this from a crash.

## What is established

Sampled with output UNBUFFERED (`stdbuf -o0`), so nothing is hidden in a block
buffer — the earlier suspicion that SIGTERM was discarding a flushed tail is
ruled out; the log really does stop:

- espide main thread: `state=D` (uninterruptible sleep),
  `wchan=anon_pipe_read`. Blocked reading a pipe, not polling one.
- Other threads are ordinary: `futex_do_wait`, `poll_schedule_timeout`,
  `ep_poll`.
- The monitor child is alive and silent: `cat /dev/serial/by-id/...`, parented
  to espide's main tid.
- The port is fine. `stty -F <port> -a` shows `clocal` SET, and a bare
  `timeout 3 cat <port>` returns 0 bytes rather than blocking in `open` — so
  this is not a carrier-detect stall, and there is simply no serial data to
  read (the program printed everything during the flash capture).
- The log freezes for at least 20 s across four samples 5 s apart.

## Hypotheses REFUTED by measurement — do not redo these

1. **The harness timeout was too short.** No: re-run warm with `timeout 900`
   and `AutoSecs 8` behaved identically.
2. **`StreamPoll(Proc, 0)` blocks on a silent child.** No: bochan row `poll
   with timeout 0 returns at once` (added with this ticket) proves it returns
   immediately for a live silent child.
3. **`ChildDone` clears `Mode` after the `case`, clobbering
   `StartMonitor`'s `mMonitor`.** No: it does `m := Mode; Mode := mIdle;`
   BEFORE the `case`, so `mMonitor` survives.
4. **`Ticker` is enabled too late.** No: `Ticker.Enabled := True` is line 1417,
   `StartBuild` is line 1434.
5. **`StreamPoll` reads an fd that `poll` did not report as readable.** This one
   is worth spelling out because it LOOKS right: `StreamPoll` breaks only on
   `ev <= 0`, and its `POLL_HUP` check happens AFTER `PalRead`, so a revents
   mask with `POLL_IN` clear would fall into a blocking read. But
   `PalBackendPoll` (posix) returns revents only when `ppoll` reported ready,
   and returns 0 on timeout — and for a pipe with a live writer and no data
   `ppoll` returns 0. So this path breaks correctly. It remains a latent
   sharp edge worth tidying, but it is not this bug.
6. **`RunCapture`'s read-to-EOF loop.** It would block exactly like this, but it
   has no call sites in espide or the garin units.

## Not yet tried

- `strace -f` was attempted and was useless: it slowed the build so much the
  monitor phase was never reached within the 300 s wait. Any retry needs to
  reach step 3 first and only then start tracing, which `ptrace_scope=1` on
  plexus makes awkward (a non-child cannot be attached).
- Which fd the blocked read is on. `/proc/<pid>/fd` plus the pipe inode would
  say whether it is the monitor child's pipe or something else entirely, and
  that is the single most useful next datum.

## Why it is filed rather than fixed

The Detect single-port fix it was found alongside is independently verified and
was landed rather than held: until it is in, any press of Detect on a
multi-board host resets boards the user did not choose, which is a live hazard
to other people's hardware. This hang predates that fix, is reachable from the
GUI Monitor button on the same code path, and costs a board run per experiment.

## Notes

- The GUI Monitor button runs the same `stty ... ; exec cat <port>` command, so
  this is very likely not `--auto`-specific. Unverified: the GUI case has not
  been driven to the same point.
- `runner.pas`'s own interface promises StreamPoll "never blocks longer than
  timeoutMs". Whatever the cause turns out to be, something on this path
  violates a documented contract.

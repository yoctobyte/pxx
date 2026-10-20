---
track: N
prio: 40
type: bug
---

# select.select skips file objects, so a Popen pipe is never ready

Found 2026-10-20 while probing for Vloot. `select.select([p.stdout], [], [], 2.0)`
returns an empty ready list immediately, even though the child writes within
the timeout. CPython reports the pipe as ready. `PySelectReady` (pylib.pas)
polls only integer entries and silently skips anything else, so a TPyFile (a
Popen pipe or an open() file) is never polled. It should take `fileno()` from
a TPyFile entry and return the original object in the ready list.
`select.select([p.stdout.fileno()], ...)` already works and matches CPython.

`os.read(fd, n)` and `os.set_blocking(fd, flag)` also don't exist ("undefined
variable (os)"), so the usual select-then-read loop can't be written yet.

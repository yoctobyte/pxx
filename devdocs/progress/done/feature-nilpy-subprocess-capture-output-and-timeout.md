---
track: N
prio: 70
type: feature
---

# subprocess: capture_output, timeout, stderr=PIPE/STDOUT, communicate, check

Found 2026-10-19 in sysdash's backend.py, which calls `subprocess.run([...],
capture_output=True, text=True, timeout=5)`. lib/rtl/subprocess.pas refused
capture_output, timeouts, stderr=PIPE/STDOUT and .communicate() on purpose, and
stderr=DEVNULL was accepted but not honoured. A collector streaming over ssh
needs the timeout most: a hung nvidia-smi stalls the stream.

**Fix:**
- PAL: `PalVforkAndExec3` also wires the child's stderr, with -2 meaning
  stderr=STDOUT. POSIX only; ESP and wasi return unsupported. The old
  subprocess.pas header named this work feature-pal-spawn-stderr-redirect, but
  that ticket was never filed.
- `run()` returns a CompletedProcess (args/returncode/stdout/stderr,
  check_returncode). It takes capture_output=, stdout=, stderr=, stdin=, text=,
  universal_newlines=, timeout= and check=. On timeout it kills the child and
  raises TimeoutExpired, as CPython does.
- `Popen.communicate(timeout=)` added, and `Popen.stderr` and `.args`. Both
  pipes are drained as one poll set, so the child cannot deadlock.
- Text mode translates line endings to \n, as CPython's universal newlines do.
- SubprocessError, TimeoutExpired and CalledProcessError use CPython's
  hierarchy and messages.
- A missing program now raises FileNotFoundError in the parent, and a
  non-executable one PermissionError. Before, the child exited 127, so
  `except OSError` never ran.
- An unsupported redirect raises ValueError instead of Halt(1).

**Two traps hit while building it:**
1. Inside `Popen.Create`, the bare constant `STDOUT` meant the `stdout`
   PARAMETER, because Pascal is case-insensitive, so stderr=STDOUT silently
   merged nothing. The code now uses the alias STDOUT_REDIRECT.
2. Exception classes must be declared in the unit the program imports. A class
   in a unit that unit merely uses is not found by `except
   subprocess.TimeoutExpired:`. pylib comes LAST in the uses clause so that
   `Exception` is pylib's (mimic_sqlite3.pas, note 1).

**Not here:** shell=True, env=, input=, wait(timeout=).

**Test:** test/test_nilpy_subprocess_capture.npy. Both existing subprocess
tests still pass.

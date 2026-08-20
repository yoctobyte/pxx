---
track: U
prio: 45
type: decide
blocked-by: []
summary: "Should a pxx binary install a SIGSEGV/SIGBUS handler by DEFAULT, so a memory fault prints `Runtime error 216` and exits 216 like FPC — or should that be opt-in behind a flag, the way FPC-style float errors are? It changes how every pxx binary dies."
status: backlog
owner: unassigned
---

# Should SEGV → runtime error 216 be default-on?

- **Track U** — a decision, not work. Blocks the default choice in
  `bug-a-a-memory-fault-is-a-raw-sigsegv-not-runtime-error-216` (the mechanism
  is the same either way; only the install list differs).

## The fork

A memory fault in a pxx binary is today a bare `Segmentation fault`, exit 139,
no message. FPC prints `Runtime error 216` and exits 216. The fix is small
either way; what needs deciding is whether it is on unless asked otherwise.

## Option A — default-on (`--no-signals` already opts out)

- FPC parity for the most common runtime fault; scripts and test harnesses that
  key on FPC's exit codes keep working.
- Consistent with the signal runtime already being default-on, whose stated
  reasoning was *"no auto-detection — predictable process behavior beats size
  sniffing; the whole runtime is ~200 bytes"*.
- Costs: no core dump by default (the handler exits before the default
  disposition can fire), and exit 139 becomes exit 216, which any existing
  crash-detection around pxx binaries would see change under it.

## Option B — opt-in behind a flag (e.g. `--fpc-runtime-errors`)

- Matches the closest precedent: FPC-style FLOAT runtime errors are opt-in
  behind `--fpc-float-errors`, with the same "turn a hardware trap into an FPC
  number" mechanism.
- A fault stays a fault: core dumps and exit 139 keep working for anyone
  debugging, which is the majority use during development.
- Costs: the out-of-the-box experience stays "Segmentation fault" with no line
  and no clue, which is the whole complaint.

## Recommendation

**Option A, default-on**, with `--no-signals` as the existing escape hatch. The
float flag is a weak precedent here because it also changes *computation* (it
unmasks FP exceptions, so a program that used to produce a NaN now dies); a
SEGV handler changes only the message on a program that was already dead. And
the argument that first made the signal runtime default-on — predictable
process behaviour — points the same way.

If A is chosen, say in the release notes that a crashing pxx binary now exits
216, because that IS the observable change.

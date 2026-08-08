---
prio: 70
status: done
owner: claude-AN
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-uforth#00 red at 378295f7c218 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-08T17:00:56Z
- **Test source:** unknown (see repro commands)

## Repro
`tools/testmgr.py --tier full --job 'test-uforth#00'` at 378295f7c218249cbb634433196aaf768ceaefb0

## Range
bad `378295f7c218`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiling uforth.py as Nil-Python ...
test-uforth: smoke PASS — compiles, STD.UFO loads, native + PYTHON-bodied words evaluate
running uforth's own corpora, DIFFERENTIAL against CPython ...
running the Forth 2012 / ANS suite per WORD SET, DIFFERENTIAL against CPython ...

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause + fix (2026-08-08, claude-AN)

**`input()` at EOF returned `''` instead of raising `EOFError`.** uforth's
`repl()` is the canonical `while True: line = input()` shape, whose ONLY exit is
that exception — so at EOF it spun forever.

### How it presented, and why the report looked empty

The job was RED as a **timeout** at 378295f and as a **fail** at 44bd7b5, with a
log tail that stopped right after `running the Forth 2012 / ANS suite per WORD
SET` and showed nothing else. That is not a truncated report: the pxx run
produced output **byte-identical to the CPython oracle all the way to the end of
core.fr** and then simply never exited, so there was no DIFF line to print.

Per word set at HEAD, only core.fr diverged; the other 12 are green:

```
DIFF wordset core.fr      OK coreplustest OK doubletest    OK exceptiontest
OK facilitytest  OK localstest  OK memorytest  OK searchordertest
OK stringtest    OK coreexttest OK blocktest   OK toolstest  OK filetest
```

### Diagnosis

`/proc/<pid>/stat` state **R** — spinning, not blocked. Five gdb PC samples
against the `--map` symbol table landed in `PyPalPoll+0x1ce`, `PyPalRead+0xa8`
and `PXXVarClear+0x15a`, called from `repl+0x764`. That is `repl()`'s
`select.select(...)` + `input()` pair, looping.

core.fr is the one word set that reaches this: its interactive `ACCEPT` test
("PLEASE TYPE UP TO 80 CHARACTERS:") consumes the driver's trailing `BYE`, so
`vm.running` stays true and the loop meets EOF instead of the quit word.

Minimal repro (`while True: input()` over empty stdin): CPython raises EOFError
on call 1; pxx returned `''` forever.

### Fix

`compiler/builtin/pylib.pas`, `pyinput`: an empty read now raises
`EOFError.Create('EOF when reading a line')`.

The distinction is only available AT THAT POINT: `pystdin_readline` keeps the
newline, so a blank line is `#10` and only a true EOF is `''`. The check
therefore has to precede the newline strip — and a blank line must still return
`''` without raising. Both arms are pinned by the test.

`pyinput_p` writes the prompt before delegating, matching CPython, which also
prints the prompt before raising.

### Verification

- `core.fr` under the driver: exit **0**, `diff` against the CPython oracle
  **empty** (was: exit 124, timeout).
- New test `test/test_nilpy_input_eof_raises.{npy,stdin,expected}`, wired into
  the Makefile beside `test_nilpy_input_builtin`. `.expected` is CPython's own
  output. Covers blank-line-vs-EOF, that it keeps raising, and that the REPL
  loop shape terminates — the EOF arm alone would pass for an implementation
  that raised on every empty result.
- `tools/gate.sh quick` GREEN (self-host fixedpoint + testmgr quick + FPC seed).
- Only `pylib.pas` changed under `compiler/builtin/`, which does NOT perturb the
  self-host fixedpoint (the compiler does not `use` pylib) — no repin needed for
  the gate. NilPy programs built with the PINNED compiler keep the old behaviour
  until the next `make pin`.

### Filed alongside

[[bug-nilpy-input-has-two-lowerings-one-discards-the-prompt]] — `parser.inc` has
two `input` arms and the `isNilPy` one at ~10745 parses the prompt and throws it
away. Every shape probed hits the other (correct) arm, so it is latent, not
live; filed rather than fixed because the right fix is deleting a path, not
guarding it.
- 2026-08-08 — resolved, commit 3054cf0d8.

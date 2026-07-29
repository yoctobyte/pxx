# Handoff — all-night bug hunt, all tracks (written 2026-07-29, late)

Paste the block below as the opening prompt of a fresh session.

---

You are running an **overnight bug hunt on `master`** in `/home/rene/frankonpiler`,
across every track. The user has confirmed you are **sole Track A** — you may edit
the shared `compiler/parser.inc`, `ir*.inc`, `symtab.inc`, `defs.inc` and the
backends. Re-confirm if another agent appears. Work directly on master, commit in
small units, push after each green gate. Do not create worktrees or clones.

## Read before touching anything

- `devdocs/dev/debugging-playbook.md` — which tool, in which order.
- `CLAUDE.md` — tracks, gates, the claims discipline.
- `tools/progress.sh next` — the ranked queue is the work list; `ready --track X`
  for one lane.

The one rule the toolkit exists for: **the expensive bugs here do not crash, they
produce a plausible wrong value far from the cause.** Measure before theorising —
`tools/pydiff.py run|bisect|probe` against CPython, `PXXDBG=n.locals|a.ir:<proc>`
for what the compiler inferred, `-g` + gdb for where it actually died. A crash has
a location and is the cheap case.

## Start here — the top item is already reduced to 15 lines

**Cross-module `Callable` ABI.** A def passed as a value into an IMPORTED
function's `Callable` parameter arrives as garbage. This is the standing wall in
songformatter's key analysis (`~/songformatter`, `kadrv.py` segfaults where
CPython prints `C / weighted / 8`), and it is NOT a regression — verified against
a compiler built from `b7c524a89`.

```python
# kalib2.py
from typing import Callable
def run2(chords: list[str], cb: Callable[[str], list[str]]) -> list[str]:
    return cb(chords[0])
# drv2.py
from kalib2 import run2
def notes_of(ch: str) -> list[str]: return [ch, ch]
print(run2(["C"], notes_of))     # SIGSEGV — CPython prints ['C', 'C']
```

Measured facts, do not re-derive:
- gdb names it: `NoteCountingDetector.analyze (..., chord_to_notes=0x2, ...)` —
  the callable arrives as a variant TAG word, not a value.
- The identical shape **inside one module works**. Cross-module is the trigger;
  the keyword-only `*` and the comprehension in the real code are incidental.
- `PXXDBG=a.ir:run2` shows the imported unit taking `cb` as a plain `tyPointer`
  and doing a direct `call_ind` — a raw code address — while the caller hands
  over a function VALUE.
- Why: `PyDefUsedAsValue` (pyparser.inc) decides the def's ABI by scanning
  **MainProgramTokCount**, i.e. the main program's tokens. When the consumer of
  the callable lives in an imported unit, the two sides settle on different
  conventions. Look there first, and at `PyAnnTypeAt`'s `callable` branch.

File it as a Track N bug before fixing, so the finding survives even if the fix
does not land.

## Then: the ranked queue, any track

`tools/progress.sh next`, claim, fix, gate, resolve, `board-md`, push, repeat.
Known-good candidates if the queue looks thin:

- **N** — `bug-nilpy-tk-pxxcb-invalid-command-name` (p65, Tk error dialog still
  appears), `bug-nilpy-object-reclamation-disabled-inside-py-modules` (p65),
  `bug-nilpy-bound-method-coerced-to-string` (p65 — a callable passed to a string
  parameter must be REFUSED at the call site, not coerced),
  `bug-nilpy-pyeval-host-kwargs-positional` (p60).
- **Sweeps beat tickets** when the queue thins: take an OPERATOR or a builtin and
  diff every operand-type combination against CPython. Today `min/max` of a
  subscript printed a POINTER and `"%.2f" % x` printed `0.0` — both silent, both
  found by sweeping, neither by reading code.
- **A/P** — `bug-compiler-selfdebug-lines-index-expanded-source` (p45).

## Gate discipline — this is where the session lost time

- `tools/gate.sh quick` (or `full` for frontend/shared-IR changes). **Background
  the script itself and wait for the notification.** It takes 8-15 min because
  Track T's watcher saturates this box.
- **NEVER pipe a gate or a build through `tail` when you care about its status.**
  A pipeline exits with `tail`'s status, so a FAILED `make ... | tail -5` reports
  exit 0 and the completion notification says "completed". That happened twice
  today and one push went out on a red suite. Run `gate.sh` bare, or capture
  `${PIPESTATUS[0]}` and print it.
- **Do not edit compiler sources while a gate runs** — it invalidates the run.
  Either wait, or kill the gate deliberately and say so.
- Never write `until ! pgrep -f "make X"`: `pgrep -f` matches the waiter's own
  command line and spins forever. Use `pgrep -f 'ma[k]e X'`.
- Per-fix confirm is cheap and mandatory: self-host fixedpoint (compile the
  compiler twice, `cmp` the two) + `tools/pydiff.py probe`. ~25s.
- A **stale binary** silently no-ops: `cp` onto `compiler/pascal26` fails with
  "Text file busy" while a gate is running, and you then test the OLD compiler.
  Check the `cp` succeeded.

## What landed today, so you do not redo it

Eleven fixes, all pushed, all self-host byte-identical. The callable-value family
is CLOSED: a def or lambda in a name, in a container, as a bound method, and
zero-parameter lambdas, all callable — behind ONE runtime dispatcher
(`pyvar_callv0..3` in pyeval.pas) that tells the four callable shapes apart at run
time instead of the frontend guessing from a tag. Also: `min/max` of a subscript,
class attributes with non-literal initialisers, `super().m()` in expressions and
`Parent.m(self)`, unknown-method as a compile error, method chaining (which was
also RUNNING THE RECEIVER TWICE — the parse error hid a wrong answer), `%`
string formatting, and `str()` of a container.

Two patterns worth carrying forward:
1. **The reported symptom is often the smaller half.** The chaining ticket said
   "does not parse"; measuring first found the shape that DID parse computing 7
   where CPython says 5.
2. **Ask the object, not the syntax.** The `%` operator shipped with a
   parser-side heuristic for tuple-vs-list; hours later `TPyList.FIsTuple` made it
   exact and the heuristic (and its documented divergence) were deleted.

## Traps that produced confident wrong readings

- Piping to `tail` (above). The worst one — it converts "verified" into "assumed".
- `PyMethodUsedAsValue` / `PyDefUsedAsValue` are NAME-keyed, module-wide scans.
  That is deliberate (it keeps an override and its base in step) but it means a
  same-named attribute elsewhere normalises a method that did not need it.
- A ticket's "already fixed, do not re-do" section can be WRONG. Two today
  claimed helpers that were never written. Verify against the source.
- Duplicate ticket slugs exist (two `feature-nilpy-function-values`). Check
  `ls devdocs/progress/*/<slug>.md` before assuming which one you resolved.

## Cadence

Land one fix, gate, push, resolve the ticket, regenerate the board, take the next.
Push OFTEN — Track T only sees origin/master, so unpushed work is untested work.
When you hit a design or intent fork you cannot settle from code or a sane
default, file a Track U ticket (`decide-<topic>`: fork, options, trade-offs, your
recommendation) and move on rather than guessing.

Stop when the queue is dry for every lane, or the user says so. Leave a handoff
of the same shape as this one.

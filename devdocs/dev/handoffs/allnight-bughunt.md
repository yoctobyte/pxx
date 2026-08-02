# Handoff — all-night bug hunt, all tracks (rewritten 2026-07-29, second night)

Paste the block below as the opening prompt of a fresh session.

---

You are running an **overnight bug hunt on `master`** in `/home/rene/frankonpiler`.
The user has confirmed you are **sole Track A** — you may edit the shared
`compiler/parser.inc`, `pyparser.inc`, `ir*.inc`, `symtab.inc`, `defs.inc` and the
backends. Re-confirm if another agent appears. Work directly on master, commit in
small units, push after each green gate. No worktrees, no clones.

## Read before touching anything

- `devdocs/dev/debugging-playbook.md` — which tool, in which order.
- `CLAUDE.md` — tracks, gates, the claims discipline.
- `tools/progress.sh next` — the ranked queue is the work list.

The rule the toolkit exists for: **the expensive bugs here do not crash, they
produce a plausible wrong value far from the cause.** Measure before theorising.
A crash has a location and is the cheap case.

## The single highest-value habit: sweep against CPython

Last night's eight fixes came from tickets; the ~20 findings that filled the
queue came from **sweeping**. The recipe, which is cheap and repeatable:

> generate one small `.py` per operator / builtin / method, with `try/except`
> around each case, run under CPython and under pxx, diff.

Two things make it work:

- **Run every binary under `timeout`.** One finding (`2.5 * "ab"`) was an
  infinite hang, which a plain test run cannot tell from a slow one.
- **Compile from the repo root.** The compiler resolves `lib/rtl` relative to
  cwd, so `pascal26 /tmp/x.py` from elsewhere dies with "no unit named
  builtinheap". This also breaks `tools/pydiff.py`, which writes its temporaries
  elsewhere — worth fixing if you touch it.

Areas already swept and **matching CPython exactly** — do not re-sweep: string
methods, slices, list/dict methods (bar three), f-strings / `%` / `.format`
(bar `%e`), iteration and comprehensions, inheritance / `super()` /
`isinstance` / `@property` / `@dataclass`, user-raised exceptions, closures /
defaults / kwargs / recursion / `global`, numerics, `in`, truthiness and
short-circuit, mutation and aliasing, nested-container printing, `json`, `re`.

Not yet swept, and where I would look next: `with`, `del`, nested functions
inside classes, `bytes`/`bytearray`, deep recursion, very large containers,
multiple inheritance, iterator invalidation, `sys.argv`/stdin, and the same
operator sweep with VARIABLES rather than literals (everything above used
literals, so the static-type paths were exercised and the variant paths were
not — that is a whole second surface).

## Start here — the queue is stocked and honest

`tools/progress.sh next`, claim, fix, gate, resolve, `board-md`, push, repeat.
The top of Track N as of this handoff, all filed with measured repros:

- `bug-nilpy-str-of-object-segfaults-when-dunder-builds-a-string` (75) — **fix
  written and gating** when this was handed off; verify it landed before
  redoing it. Root cause: a field whose name matches a CLASS name
  (case-insensitively) was typed as that class.
- `bug-nilpy-dict-equality-compares-identity` (70) — `{"k":1} == {"k":1}` is
  False. Lists are already right; pylib has `pylist_eq` and needs `pydict_eq`
  beside it, plus an arm in ir.inc mirroring the list one.
- `bug-nilpy-eq-dunder-ignored` (70) — `__eq__` never called. `__lt__` and
  `__len__` DO dispatch, so it is wiring, not machinery.
- `bug-nilpy-runtime-raised-errors-bypass-try-except` (65) — **the best
  value-for-effort item on the board.** NOTHING the runtime raises is catchable
  (index, key, division by zero, `int("abc")`), not even by bare `except:`,
  while user `raise` works. `PyIndexError`/`PyKeyError` in `pylib.pas` are
  `writeln` + `Halt(1)` and the exception classes are declared a few lines
  above. Folds in `bug-nilpy-int-parse-halts-instead-of-raising` (55).
- `feature-nilpy-container-method-gaps` (60) — `list.index` is the LAST compile
  blocker for songformatter's remaining two modules. `list.remove`, `list.copy`
  and one-argument `dict.pop` are in the same ticket.
- `bug-nilpy-zip-over-a-string-yields-nothing-or-segfaults` (70),
  `bug-nilpy-returning-a-nested-def-yields-none` (70),
  `bug-nilpy-large-float-str-overruns-into-garbage` (70 — writes invalid UTF-8
  bytes to stdout).

Two items were deliberately PARKED with their measurements written down rather
than guessed at — read those sections before restarting either:

- `bug-nilpy-returning-a-nested-def-yields-none` (70) — the IR diff is in the
  ticket: a top-level def returns its ADDRESS and works; a nested def gets
  WRAPPED (`f(addr, 0, 1)`) and the wrapper is what the call site cannot
  invoke. Two neighbouring compile-level gaps were split out into
  `bug-nilpy-function-value-call-gaps`.
- `bug-nilpy-str-of-literal-none-prints-zero` (65) — the fix site is named
  (`ParseFactor`'s `tkNil` arm builds an integer 0), along with why the
  one-line blanket version is unsafe: the ARC rebind arm and the
  `Optional[int]` sentinel both depend on that literal being a scalar. Do it
  with `bug-nilpy-none-equals-zero-is-true`, in one audited pass.

One Track U item is waiting on the user: `decide-nilpy-mixed-type-operand-policy`
— what NilPy should do when an operator gets operand types Python rejects. Three
crashes/hangs hang off it. Do not guess the policy; the individual crashes are
filed as bugs and can be fixed without it.

## Gate discipline — where time is actually lost

- **`tools/gate.sh quick` per fix, then push — for every change, including
  frontend and shared-IR ones.** This bullet used to add "or `full` for frontend
  / shared-IR changes"; that is superseded. `quick` is ~30s (self-host
  fixedpoint + `testmgr --tier quick`; `test-nilpy` was removed from it, having
  been 625 of the gate's 649 seconds). Breadth is Track T's, run against your
  exact SHA — so widening the local gate buys nothing and delays the push, and
  unpushed work is work T cannot see. Full gates are yours only when T is
  **proven** down (`tools/twatch.py --status` exit 1).
  **Background the script and wait for the notification.** With Track T's
  watcher on this box a *full* gate took **~20 minutes** — one more reason not
  to reach for one; do useful read-only work meanwhile if you must run it.
- **Background it with an absolute path** (`/home/rene/frankonpiler/tools/gate.sh
  full`). A backgrounded relative path silently failed with exit 127 and no gate
  ran at all — the notification said "failed", which is easy to skim past.
- **Never pipe a gate or build through `tail`** when you care about the status:
  a pipeline exits with `tail`'s status, so a FAILED `make ... | tail -5` reports
  exit 0.
- **Do not edit compiler sources while a gate runs.** Ticket and memory writing
  is the right work for that window, and there is always plenty.
- Never write `until ! pgrep -f "make X"` — `pgrep -f` matches the waiter's own
  command line and spins forever.
- A **stale binary** silently no-ops: `cp` onto `compiler/pascal26` fails with
  "Text file busy" during a gate, and you then test the OLD compiler.

## What landed, so you do not redo it

Eleven changes, each `tools/gate.sh full` GREEN with the self-host fixedpoint
byte-identical, all pushed:

| commit | fix |
| --- | --- |
| 242b96878 | `from m import f` forced the function-object ABI on every def an imported module exports |
| 33db0107d | object reclamation was dead inside imported `.py` modules — nine sites now share one predicate, `NilPyUserCode` |
| 9b4b9d36c | `3 == "ab"` segfaulted |
| ee6e310b2 | a field named like a CLASS bound to that class, so `str(obj)` segfaulted |
| c4cbf2ea5 | dict `==` compared identity (+ the `TPyDict` arm in `PyVarEq` that nested dicts exposed) |
| 6735ad34e | `__eq__` was never dispatched by `==`/`!=` |
| e91ea31a0 | NOTHING the runtime raised was catchable — index, key, `int("abc")`, and a new `ZeroDivisionError` |
| 382cf7a90 | `str(3 % 2.5)` printed the double's bit pattern |
| 8cef67f5c | `list.index` / `list.remove` / `list.copy` / one-argument `dict.pop` |
| 1c8d09b71 | `FloatToStr` wrote a NON-DIGIT byte past Int64 (`1e19` → `…809.o72036…`) |
| 3c90daa64 | the re-pin that fix required (v230) |
| eaf0490e4 | `zip(list, str)` walked a string as a TPyList — silently empty, or a SEGFAULT after any earlier loop |

**`NilPyUserCode` (symtab.inc) is the one to know about**: every NilPy-only ARC
rule reads it. Grep for it before adding another — the nine rules must move
together, and nine copies of the condition is exactly how they drifted apart.

Together these took down songformatter's standing `Callable` wall: `kadrv.py`
prints `C / weighted / 8`, matching CPython, and four of its five modules
compile. The last two stop on a reportlab shim gap, filed for Track B.

## A gate rule that cost a full cycle

**A change to `compiler/builtin/**` makes `gate.sh`'s self-host fixedpoint
report RED even when nothing is broken.** That step seeds from the PINNED
binary, and `make pin` FREEZES `compiler/builtin/*.pas` into
`stable_linux_amd64/default/builtin/`, which the pinned binary prefers over the
live tree. So stage A links the OLD builtin and B/C the new one: A != B, B == C.

The tell that it is not a regression: `make test`'s own self-host seeds from the
CURRENT compiler and passes on the first generation. Compare the sh-A/sh-B/sh-C
sizes in the gate's log dir.

Remedy: `make stabilize` → `make pin` (host only) → re-run `gate.sh quick` to
confirm A == B == C → commit `stable_linux_amd64/**` WITH the source change, and
check `git status` for a newly-frozen UNTRACKED file. `pylib.pas` is frozen there
too but never triggers this, because the compiler does not `use` it.

## Traps that produced confident wrong readings

- **Three wrong root causes in a row on one bug.** "`__repr__` is
  unimplemented", "`str(self.v)` recurses", "the managed Result slot is
  uninitialised" — each plausible, each wrong, each a round. What settled it in
  ONE command was `PXXDBG=a.ir:<proc>` on a crashing and a working program,
  diffed: one node differed, `tk=6` against `tk=13`. When two programs differ by
  one line and one crashes, diff their IR before forming a theory.
- **Vary the NAME.** The same bug's trigger turned out to be the CLASS NAME, not
  the code. Holding the body fixed and changing identifiers is a cheap axis that
  nothing else would have found.
- **A generator bug looks like a compiler bug.** Two "findings" were my own
  test-generator emitting `"len("abc")"` with nested quotes. Read the generated
  source before believing a parse error.
- **A ticket can be stale in either direction.** One claimed helpers that were
  never written; another described as unfixed work that had landed the day
  before. Check the code, and `git log -S` the symbol.

## Cadence

Land one fix, gate, push, resolve the ticket, regenerate the board, take the
next. Push OFTEN — Track T only sees origin/master, so unpushed work is untested
work. When you hit a design or intent fork you cannot settle from code or a sane
default, file a Track U ticket (`decide-<topic>`) and move on rather than
guessing.

Stop when the queue is dry for every lane, or the user says so. Leave a handoff
of the same shape as this one.

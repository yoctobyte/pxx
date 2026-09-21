# TSP wall rows 4–8: what shares a cause, 2026-09-21 (frankH)

Companion to `tsp-compile-wall-inventory-2026-09-20.md`, which listed these five
as *"ordinary, contained, ours"*. Worked as a GROUP rather than one ticket at a
time, because you cannot notice that two of them share a mechanism while holding
one of them. **One of the five was not ordinary.**

All five reproduced at pxx `8e60c44be` against TSP's live tree, `--threadsafe`,
`-Fu lib/rtl`. The first-error line for each is below and each was checked
against what that line actually holds.

## The grouping

| row | wall | mechanism | shares with |
| --- | --- | --- | --- |
| 4 | `dataclasses.replace` | qualified member of a **consumed-only root**; its cheap lowering needs row 8 | **7** (symptom), **8** (implementation) |
| 5 | `@dataclass(frozen=True)` | dataclass codegen; the refusal is correct | — |
| 6 | `subprocess.run(cwd=)` | a real unit, a missing parameter | — |
| 7 | `random.Random(seed)` | qualified member of a **consumed-only root** | **4** |
| 8 | keyword through a callable value | marshalling (`pyvar_callv_kw`) — `tsp/departure.py:531` (CORRECTED 2026-09-21; was `historic.py:531`) | **4** (row 4's cheap lowering needs it) |

**Rows 4 and 7 are one mechanism with two failure surfaces**, and that is the
finding. A *consumed-only root* is a module the compiler consumes at the import
and publishes no unit for — `sys`, `os`, `textwrap`, `select`, `typing`,
`itertools`, `dataclasses`, `__future__`, `collections`, `random`. What the
compiler provides for these it provides through the QUALIFIED intercepts, of
which `PyStdlibCallProc` is the call table. So a qualified member of such a root
is answered by a table lookup, and there are exactly two ways to get it wrong:

- **Nothing answers** → `undefined variable (dataclasses)`. Row 4. Loud, honest,
  a plain missing feature.
- **The WRONG thing answers** → row 7, below. Not loud, and not honest.

Row 6 is not this at all: `subprocess` has a real backing unit
(`lib/rtl/subprocess.pas`) and `run` simply has no `cwd` parameter. Reading it
as a sibling of 4 and 7 would send someone to the wrong machinery.

## Row 7 is not a missing feature — it is a silent wrong value

The inventory characterised it as *"per-instance RNG class absent"*, p40,
ordinary. **That is wrong.** `PyStdlibCallProc`'s callers lower-cased the member
before looking it up, so `random.Random` folded onto `random.random` and
resolved to the **function**:

    import random
    r = random.Random()
    print(type(r).__name__)      # CPython: Random      pxx (before): float

With a seed it produced `pyrandom_random takes fewer arguments than were given`,
which reads like a missing feature — **that diagnostic is what put this row in
the note as an ordinary gap.** With no argument it compiled clean and evaluated
to a float, in the one place a program asks for a source of randomness and has
no way to tell it got the wrong thing.

**THE CENSUS COULD NOT HAVE SEEN THE WORSE SPELLING.** Its oracle is compile
success, so the seeded form scored as a refusal and the unseeded form — the
silent one — would have scored as a PASS.

### Why the construct could not have been right anywhere

**Every key in that table is a genuine all-lowercase Python name.** So a
case-insensitive match can never find a real entry that an exact match misses.
It has no true-positive population at all — it can only manufacture a FALSE
match. That is a guard-that-cannot-fail one level down, and it is established by
reasoning about the key space rather than by trying spellings.

Fixed by matching the member **as spelled** at the four sites that folded it,
with the reason recorded in `PyStdlibCallProc`'s header rather than at any one
call site.

**The guard's positive control is the PIN, and it needed no rebuild.** Pin v413
predates the fix: it compiles `test/nilpy_random_class_probe.npy` rc=0 and
prints `float`, where the fixed compiler refuses. That matters beyond this row —
the usual way to prove a guard can fail is revert → rebuild → restore → rebuild,
which CLAUDE.md warns walks the local seed off the pin-derived chain, and here it
was not merely expensive but **unavailable**: the tier validating this same
change was holding `compiler/pascal26` for 45 minutes. Written up as a standing
technique in `debugging-playbook.md`, with the pin→commit mapping measured over
all 404 rows of `stable_linux_amd64/default/pin.log`.

### The sibling grep, done as a census with its population printed

*Fixed one arm of a double case? Grep for the sibling before closing.* The
question that outlives the fix is how many OTHER capitalised members were
folding onto a real lowercase key — each one another silent wrong value a
compile-success oracle cannot see.

Population: **all 72 keys** of `PyStdlibCallProc`, extracted from the source and
resolved against CPython 3.14.4 — **72 resolved, 0 skipped** (the `dict.` and
`str.` keys resolve through `builtins`, which an `importlib`-only walk silently
drops; that gap was closed rather than left in the denominator). For each key,
every real attribute of its container whose lowercase equals the key's member:

    collisions: random.random  <- random.Random          (1 of 72)

**Exactly one.** `queue.Queue` and `threading.Thread` — the candidates raised
from the demo corpus, and the right ones to raise — cannot reach this table at
all: the dispatcher admits only `os sys textwrap select dict math random str
time collections` as bases. Confirmed behaviourally rather than by reading the
list: `queue.Queue()` compiles and answers `Queue`.

## Corrections to the inventory that this pass produced

- **`commentary.py` is NOT a `random.Random` row at HEAD.** It walls at
  `pascal26:79` on `threading.Condition`, and `commentary.py:79` is a `def`. The
  error is in the **imported** `voice.py:79`, printed with that module's line
  number and no file name. `smoke.py:60` is the genuine `random.Random` site.
  Caught by looking at what the blamed line actually holds.
- **`type(collections.deque()).__name__` answers `TPyDeque`, not `deque`.**
  Found as a false hit in this change's own positive control, and attributed to
  the **pinned** compiler before being blamed on the change — it reproduces
  there, so it is pre-existing. Same shape as `lib/rtl/pil.pas`'s
  `Image = TPILImage`: the alias makes the NAME resolve while `__name__` keeps
  reporting the Pascal spelling. Introspection only; filed separately.

## Row 6 is mechanically one line and the cost is the signature

`subprocess.run(argv, cwd=HERE)` — `tsp/menu.py:141` and `:161`. The refusal is
honest: `lib/rtl/subprocess.pas` declares `run(const argv: Variant)` and nothing
else.

**The correction that decides the implementation, and it is the opposite of what
the first reading suggests.** The obvious cheap fix is for the PARENT to
`chdir`, spawn, and `chdir` back — racy, and unnecessary, because
`PalBackendVforkAndExec` **does a real `fork` despite its name** (its own
comment says so, and the reason is that the child runs a Pascal path before
`execve`). So the child already executes code of ours between fork and exec —
that is where `dup2`/`close` happen — and a `chdir` there affects the child
only. `SYS_chdir` is already present in the posix backend.

So: one syscall in an arm that exists, and a `cwd` parameter threaded through
`run`, `call`, `Popen.Create`, `PalVforkAndExec` and **three** PAL backends
(posix, esp, wasi), interface and body. Cross-target surface, so the honest gate
is a cross build rather than `test-nilpy`. Filed, not started.

## AND ROW 4 IS COUPLED TO ROW 8 — through the implementation, not the symptom

Found by asking what row 4 would actually cost, rather than by comparing its
error message to anything. **CPython 3.13+ generates `__replace__` on every
dataclass and defines `dataclasses.replace(obj, **kw)` in terms of it**
(verified against 3.14.4, not recalled). So the cheap lowering of row 4 is
`x.__replace__(k=v, ...)` — CPython's own semantics — and each generated method
knows its own fields at COMPILE time. The reflective "allocate an instance of a
run-time-known class" capability its ticket is named for is not needed.

But `x.__replace__(k=v, ...)` is a **keyword call through a dynamic receiver**,
which is row 8. The two rows sit at opposite ends of the board and one is a
prerequisite of the other's cheap path.

**And the hazard is the reason this paragraph exists rather than a note in a
ticket.** A dynamic-receiver method call here resolves by scanning declared
classes FOR THE NAME and hard-casting to the first hit with no runtime class
test — the family behind lekkerzeilen blockers 03 and 04. Generating
`__replace__` on every dataclass manufactures **the exact population that
defeats a first-wins scan**: one name declared by N unrelated classes. Today
that family fires when two or three classes happen to share a name; here it
would be every dataclass in the program, and the failure would not be a
diagnostic — it is a hard cast to a class the program never named.
`tsp/shape.py:115`'s receiver is a dict value in a comprehension, so it is
dynamic precisely where this bites.

Order, therefore: row 8, then the receiver-scan fix, then row 4. **Taking row 4
first trades a loud refusal for a silent wrong object**, which is worse than
today.

## Row 8 is placed: `tsp/departure.py:531`  (CORRECTED 2026-09-21)

**Was `historic.py:531` — that file is 284 lines and has no such line.** The
no-filename trap this very document describes for the threading rows. Confirmed
by elimination: six modules under `tsp/` have a line 531 and only `departure.py`
matches both halves of the diagnostic (>4 positional AND a keyword).
**Compiling `departure.py` directly is CLEAN** — it fires only through
`historic.py:26`'s import.

    Nil Python: a keyword argument through a callable value needs
    pyvar_callv_kw (pyeval) and at most 4 positional arguments

Recorded as unplaced for most of this note's life, because it came off a census
COLUMN rather than from a reproduction. Filled by one targeted sweep — run only
after asking the seat holding the box, who **was** timing (a 9% effect against a
17% spread under load; the sweep would have sat inside the error bar) and who
had moved back onto wall clock twenty minutes earlier without saying so. Asking
cost one line; assuming would have cost them a leg.

## THE SWEEP ALSO ANSWERS A "HOW MUCH" THE FIRST-FAILURE CENSUS CANNOT

Full re-run at pxx `8e60c44be` + this change, `--threadsafe`, population
`find tsp -name '*.py'` = **67**, failures **20** — so **47 of 67**, the same
number as `45b8571d7`.

**`wave` landing delivered ZERO units, measured rather than predicted.** That is
the caveat from the inventory turning into a result: clearing a wall moved
`voice.py` to the next one and moved the count not at all.

And the composition hides a collapse worth having. Three rows report
`threading.Condition` at **line 79** — `commentary.py`, `__main__.py`,
`voice.py`. They are **ONE site**: `commentary.py:79` is a `def` and
`__main__.py:79` is `if args.at:`; only `voice.py:79` is
`self._cv = threading.Condition()`, and the other two import it. An error inside
an imported module prints that module's line number with no file name, so the
reader supplies the file they invoked.

    threading rows:  3 files  ->  1 site  (voice.py:79)
    ctypes rows:    10 files  ->  the seam, already known

So the honest reading of the board is **not** "three threading defects". It is
one missing `threading.Condition`, behind which at least three files sit — a
*lower* bound on yield for once, where a first-failure census normally gives an
*upper* bound on cause count. `provider.py` also imports `voice` and is behind
`frozen=True` as well, so it needs both.

Which is the general point this note keeps arriving at from different
directions: **the census counts DIAGNOSTICS, and a diagnostic is not a cause, a
site, or a unit.**

## What is NOT established

- No claim that rows 5 and 6 are unrelated to anything — only that they are not
  the rows-4-and-7 mechanism. Both were READ: row 5's refusal site in
  `PyParseDataclassArgs`, row 6's spawn path down to the syscall.
- Row 8 is now REPRODUCED (`tsp/departure.py:531` — CORRECTED 2026-09-21, and
  only via `historic.py`; the direct compile is clean), but its mechanism is read
  from the diagnostic rather than from the code — weaker than rows 4–7, where
  the machinery itself was opened. (This list used to say "each was read",
  which was true of four rows and written across five; then said row 8 was
  unplaced, which was true for two hours.)
- Clearing any of these is **not** promised to deliver its file. `wave` cleared
  the day before and delivered nothing (`voice.py` moved to
  `threading.Condition`). The instrument reports the first error per file.

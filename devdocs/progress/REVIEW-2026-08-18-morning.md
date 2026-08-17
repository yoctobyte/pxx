# Morning review — the overnight run of 2026-08-17

**Read time: ~4 minutes.** Written for the stated goal: read decisions, not bug
reports. Updated at each hourly check; the operational detail is in
`devdocs/dev/session-roster.md` and the tickets, not here.

---

## Decisions waiting on you

`tools/progress.sh ready --track U` is the live list. As of the start of the run:

| ticket | prio | what changes on your answer |
| --- | ---: | --- |
| `decide-week-theme-2026-08-17` | 70 | Largely answered by measurement — finish-NilPy and push-the-corpora turned out to be the same week. Probably now a confirmation rather than a fork. |
| `decide-what-an-unwired-test-may-assert` | 55 | Whether ~61 compiling-but-unwired test files may record their own current output as `.expected`. Recommendation: never — compile-and-run as the floor, oracle comparison where one exists. |
| `decide-staff-track-c-to-unblock-own-language-first` | 50 | Staffing. |
| `decide-nilpy-exec-injects-a-builtins-key` | 40 | Semantics. |
| `meta-float-accuracy-policy` | 40 | Policy. |

**Also needs a call, not yet a ticket:** Track A had three tickets filed today
with no Track A worker, which is why frank2 was cleared and re-laned mid-evening.
That worked, but it means Track N is now unstaffed and has real queued work.
Whether that is the right steady state is yours.

## Rulings you gave today, now load-bearing

Recorded because they settled work rather than merely answering a question:

- **`--no-shims` is "unsupported"** — we provide no shims, nothing is promised past
  the opt-out, and it is **not to be hardened**. The operative half was *"not
  sneakily load other shims"*, which is what settled where a Python-shaped shim
  lives: `mimic_six.py`, because the tree must say what each shim is. Complicating
  the common path to defend an opt-in audit flag was rejected.
- **Synapse is a test surface, not a dependency** — we have our own TCP stack and
  SSL. Deprioritised the config ticket 45 -> 20 and, more usefully, produced a
  general rule now in `frontend-compat-philosophy.md`: *a corpus is a measuring
  instrument, and difficulty compiling an old one is expected cost, not a bug
  signal.*
- **Float work is low priority** — including formatting, and including a
  performance defect that merely lives in float code. The coordinator broke this
  twice by reclassifying; recorded as: a standing priority ruling is not
  re-litigated by finding another category the ticket also fits.
- **Third-party source never enters the repo** — verified clean (both roots
  gitignored, zero tracked, zero ever added on any branch) and now **enforced**
  rather than documented, by a check in the gate every fix runs.

## What shipped

Compiler (Track A):
- `@procvar` in Delphi mode carries the pointer it holds — root cause of a TLS
  handshake jumping into the stack. Found via an FPC differential; the crash site
  named the wrong subsystem entirely.
- A NilPy module could be compiled and **initialised twice** (two unit rows for one
  file): import-time registration ran twice and two class copies failed `isinstance`
  against each other. Visible output was correct, which is what made it expensive.
- Parent-relative imports (`from ..constants import X`) ignored the dot **level**.
- The shim slot now finds a Python-shaped shim, and three latent bugs in the same
  lookup were fixed with it — one of which was already breaking `.pas` shims from
  any directory other than the repo root.

Libraries (Track B):
- `mimic_six`, the builtin `Warning` hierarchy (all twelve names, read off CPython
  3.12), the dlopen loader **gated for the first time**, `HModule` placed where FPC
  actually keeps it, and a quadratic string build in `strtofloat` (3.1x / 2.2x).

Infrastructure:
- Track T full tier **GREEN: 2695 jobs, zero corpus skips.**
- The synapse corpus is now fetchable, discoverable and **pinned**; it had been
  tracking `origin/master` unpinned, so no two checkouts were guaranteed the same
  source.
- A wiring checker found **98 test files that no build rule ran**. The ten that
  shipped alongside fixes in the last two days are now wired; the rest are triaged.

## The theme, if you want one

Nearly every expensive thing today was **a true statement about the wrong subject**,
and the tally is roughly even between the coordinator and the workers:

- `2 skip (corpus absent)` — true in every report for two months, and the cause was
  Track T's own message wrongly claiming the corpora were unfetchable.
- A test asserting `@fpNil <> 0` — true under *two* of three candidate answers, so
  it had been green for the wrong reason.
- A differential built over its own control binary — clean, repeatable, and measuring
  the wrong build.
- `find -name '*.cfg'` returning nothing — taken as "the library config was never
  built", twice, the second time with commit shas attached.
- 6-7 corpus files blocked on `webencodings` — an artefact of the scan passing one
  `-Fu` root, which ranked a non-existent compiler bug as the top lever.

The rule that came out of it, and the one worth keeping: **ask which other
candidate answers would also satisfy the check.** If more than one would, it is not
testing what its name says. Its corollaries — the evidence must sit outside the
thing being varied; a ticket's *cause* ages faster than its *symptom*; a constant
nobody can explain is a wound until proven a baseline — are all the same rule from
different angles.

## Open at the time of writing

- frank2 (A) → `feature-port-rtl-over-libc` (p55, unblocks 3).
- frank3 (B) → `mimic_warnings`, the last wall on 3 corpus files.
- Pin at **v346**. Track T's agent is down; its watcher is up and files stubs itself.

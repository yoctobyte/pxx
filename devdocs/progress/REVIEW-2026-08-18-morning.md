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

## One bug you may want to look at yourself

`bug-n-a-type-as-a-default-parameter-value-segfaults-when-the-default-is-taken`
(N, p60). Found by Track B while writing `mimic_warnings`; **reproduced
independently here** before it went in this digest:

    class W: pass
    def f(c=W): print(c.__name__)
    f()          -> exit 139, segfault, NO diagnostic

The same class passed explicitly prints `W` and exits 0, so the fault is in
materialising the default, not in using a type as a value.

Two things make it worth your attention rather than just the queue. It is
**silent** — every other type-as-a-value gap in this dialect gives a clean refusal
(`the class W cannot be used as a VALUE yet`), and a dialect that refuses
consistently and then dumps core in one corner is worse than one that refuses
everywhere, because the refusals are what teach people to trust the diagnostics.
And `category=SomeClass` is an ordinary Python signature idiom, so this breaks the
upward-compatibility contract on code CPython runs without complaint.

Track B did **not** reshape around it: it used the sanctioned route
(`category=None` + substitute), registered in `track-b-workarounds.md` with a
revert-to note, and the test's warn-with-no-category line is that workaround's own
regression guard. That is the pattern working exactly as designed.

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

**And the sharpest one, found at the end of the night:** a Track A ticket's
acceptance criterion was *"the emitted binary contains zero `syscall`
instructions — verify with `objdump -d | grep -c syscall`"*. pxx writes ELFs with
program headers only and **no section headers**, and `objdump -d` disassembles
sections — so it prints a three-line header and then `0`, for every pxx binary
ever built. Reproduced here on `compiler/pascal26`: `objdump` says **0**, a
correct instrument says **1093**. That test would have passed on day one and kept
passing whatever the port did.

It is a category worse than the others: those checks could not *discriminate*
between candidate answers; this one **cannot fail at all**. The replacement
(`tools/syscall_scan.py`) fixes the family, not the instance — it reads program
headers, uses per-arch mnemonics (the word "syscall" reports a clean zero on every
cross target regardless of truth), and **refuses to report a count it could not
measure**, because an instrument that cannot distinguish *measured zero* from
*failed to measure* will eventually report the second as the first.

The rule that came out of it, and the one worth keeping: **ask which other
candidate answers would also satisfy the check.** If more than one would, it is not
testing what its name says. Its corollaries — the evidence must sit outside the
thing being varied; a ticket's *cause* ages faster than its *symptom*; a constant
nobody can explain is a wound until proven a baseline — are all the same rule from
different angles.

## Housekeeping for the morning (not done overnight, deliberately)

`tools/progress.sh check` reports **17 resolved tickets awaiting their landed sha**
(`tools/sync.sh` fills them in) and 3 STATUS-DRIFT lines where a ticket's body says
`working` while its folder says otherwise. Both are bookkeeping. Not run overnight
because `sync.sh` pushes on behalf of other lanes' resolves, and doing that
unsupervised is the kind of helpfulness that is hard to unpick.

## Open at the time of writing

- frank2 (A) → `feature-port-rtl-over-libc` **PARKED in `unfinished/`, and the park
  is clean** — verified independently: zero `compiler/` and zero `lib/` diff, no
  CRITICAL from `progress.sh check`. It stopped at synthesising PLT imports from
  codegen with the self-host fixedpoint riding on it, which is not overnight work.
  It leaves behind a working acceptance instrument, real baselines (pxx hello-world
  57, one libc call 55, `/bin/true` 0), a corrected criterion, and a smaller plan:
  libc calls already work with no compiler change, and all 62 raw-syscall sites
  across 11 RTL units funnel through **one** `IR_SYSCALL` op, so the port needs no
  `lib/rtl` edits at all.
- frank2 then pulling its own next Track A item, excluding the policy ticket.
- frank3 (B) → `mimic_warnings` **landed**; `feature-nilpy-six-and-warnings-shims`
  resolved, both halves. `warnings` has left the first-wall table on all three files
  that import it — same shape as `six`. Now on the `string.digits` gap, the next
  wall on those files.
- Pin at **v346**. Track T's agent is down; its watcher is up and files stubs itself.

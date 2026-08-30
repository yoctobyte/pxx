---
track: T
prio: 45
type: task
status: backlog
blocked-by: []
owner: ""
summary: "Of the four C corpora the repo treats as its real-program coverage -- lua, zlib, quickjs, tcc -- only lua and zlib are in a testmgr tier. test-quickjs exists in the Makefile and is enrolled in NO tier; test-tcc does not exist at all (TCC_SRC appears 0 times) though install_lib_candidates.sh can fetch it. And test-quickjs self-skips exit 0 on a box without the tree, so enrolling it alone would still assert nothing while reporting success."
---

# The C corpus is two rungs, not four — and a missing tree reports PASS

- **Track T** — tier composition and the report format (`tools/testmgr.py`).
- **Found:** 2026-08-30 by frankC, checking what §6 of
  `feature-c-import-a-pascal-unit-under-a-mangled-name` would actually measure
  before running it. Filed at the user's request.
- **T owns the tool, never the bug** — there is no compiler defect here. This is
  a coverage/reporting gap in T's own ground.

## The measurement

§6 of the mangled-name spec says *"build the C corpus — lua, tcc, quickjs,
zlib."* Measured at HEAD:

| corpus | Makefile target | in a testmgr tier? |
| --- | --- | --- |
| `test-lua` | yes | **yes** — `limited` + `full` |
| `test-zlib` | yes | **yes** — `limited` + `full` |
| `test-quickjs` | yes (`Makefile:14634`) | **no tier at all** |
| `test-tcc` | **does not exist** — `TCC_SRC` appears 0 times in the Makefile | — |

So a claim of the form *"the C corpus is green at sha X"* is today a claim about
**half** the corpora the repo names, and nothing says so at the point the claim
is made.

## Three separate defects, and the third is the one that generalises

### 1. `test-quickjs` is written but unenrolled

The recipe is complete — it compiles `test/quickjs/runner.c` against the quickjs
tree, runs a curated JS smoke byte-exact against `smoke.expected`, then runs a
js-sha256 library case. None of it is in `quick`, `limited` or `full`. It runs
only if someone types it.

This is the state `testmgr.py`'s own tier comments already describe as the reason
`test-fgl` / `test-fpjson` were enrolled on 2026-08-26:

> `test-fpjson` was in NO tier, landed at 203/203, and had rotted to
> not-compiling by the first hand-run since. **An unenrolled check asserts
> nothing while reporting success.**

`test-quickjs` is in exactly that position now, which suggests the 2026-08-26
enrolment pass fixed the two rungs it was looking at rather than sweeping for the
class.

### 2. `test-tcc` was never written

`tools/install_lib_candidates.sh` has known tcc all along — `fetch_tcc` at :408,
`TCC_URL` / `TCC_COMMIT` pinned to `a338258d309c` (mob, 2026-07 snapshot), a
generated `config.h` + `tccdefs_.h` step, and a `PROVENANCE.md`. So the *source*
side is done and the *test* side does not exist: nothing in the Makefile ever
references `TCC_SRC`.

**The tcc tree is also simply absent on plexus** — per the user, a relic of borg
being temporarily down, not a decision. Re-fetching is
`tools/install_lib_candidates.sh tcc`.

**Do NOT vendor it.** Third-party source stays out of this repo and arrives
through the installer; `tools/check_no_vendor_tracked.sh` exists to enforce
exactly that. Any rung added here must follow `test-quickjs`'s shape — a
`?=`-defaulted `*_SRC` pointing into `library_candidates/`, never a checked-in
tree.

### 3. A missing tree reports PASS — so enrolling (1) alone would not be enough

`test-quickjs` opens:

```make
@if [ ! -f "$(QUICKJS_SRC)/quickjs.c" ]; then \
  echo "test-quickjs: SKIP — no quickjs tree at $(QUICKJS_SRC) ..."; \
  exit 0; \
fi
```

**`exit 0`.** On any box without the tree, the rung prints SKIP and the tier
counts a pass. Enrol it as-is and every box that has not run
`install_lib_candidates.sh quickjs` reports green corpus coverage it does not
have — the same outcome as not enrolling it, now wearing a passing badge.

That is `test-fgl`'s exact history repeating one level in: it *was* inside
`test-core`, guarded on `/usr/share/fpcsrc`, so it "printed `SKIP (no fpcsrc)`
and PASSED for its entire life without running once."

**This is the repo's own rule, in T's own ground:** *"'ruled out' and 'could not
look' must never print the same."* A skip is not a verdict. Whatever shape the
fix takes, the tier's report must be able to distinguish *ran and passed* from
*could not run*, and a box that cannot run a corpus rung should say so in the
tstate report rather than being counted green.

## Suggested shape (T's call, not mine)

1. A `test-tcc` rung modelled on `test-quickjs`, `TCC_SRC ?= library_candidates/tcc`.
2. Enrol `test-quickjs` and `test-tcc` in `limited` + `full` beside `test-lua` /
   `test-zlib` / `test-cjson`.
3. **First**, make a self-skip visible in the tier verdict — a distinct SKIPPED
   state, not a silent pass. Doing (2) before (3) buys a badge and no coverage.
4. Fetch the trees on plexus (`install_lib_candidates.sh quickjs tcc`).

Ordering matters: (3) is the one that makes (1) and (2) mean anything.

## Why it was worth filing rather than just running the installer

The trees being absent is a one-command fix. The rungs being absent from every
tier is not, and it is invisible from the outside: `--tier full` GREEN reads as
"the corpus is green" to every lane that consumes tstate, and two of the four
corpora are not in it. The verdict is not wrong, but it is narrower than every
reader takes it to be.

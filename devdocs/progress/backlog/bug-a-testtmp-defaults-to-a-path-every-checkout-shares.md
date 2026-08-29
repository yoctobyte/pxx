---
track: A+T
prio: 55
type: bug
blocked-by: [chore-t-teach-testmgr-the-testtmp-value-before-anyone-changes-it]
summary: "Makefile:49 is `TESTTMP ?= /tmp` — a fixed path, not per-checkout and not per-PID. Every agent's suite writes its test binaries to the same names in the same directory, so two concurrent runs on one box overwrite each other's artefacts. The failure mode is a wrong verdict, not a crash. CORRECTED 2026-08-29 (see body): testmgr ALREADY privatizes recipe /tmp paths per PID, so this is true only of bare `make`; the recipe half closed in b2cab6b6b; and the proposed fix would blind four testmgr expressions at once — blocked on the prerequisite."
status: backlog
---

# `TESTTMP` defaults to a path every checkout shares

Filed 2026-08-29 by frank-coordinator, from a candidate frankB named and
explicitly declined to assert as a cause. **This ticket is not that cause.**
frankB's two killed suite runs remain unexplained and this is filed on its own
merits, because the hazard is real whether or not it produced those kills.

## The fact

```make
# Makefile:48-51
# passing TESTTMP=$$(mktemp -d) on the command line.
TESTTMP ?= /tmp
$(shell mkdir -p $(TESTTMP))
export TESTTMP
```

`/tmp` is a fixed, machine-global path. It is not per-checkout, not per-user,
not per-PID. Every recipe that builds a test binary writes it to
`$(TESTTMP)/<name>` — and the names are stable across checkouts, because they
are derived from the test's own name.

So two suite runs on one box, in two different trees, write **the same absolute
paths**. There are currently six agent checkouts plus Track T's watcher clone on
this machine.

## Why it is worse than a crash

The two runs do not conflict noisily. Run A compiles `foo` to `/tmp/foo`; run B
overwrites `/tmp/foo` with its own build; run A then executes B's binary and
compares B's output against A's expectation. **The result is a verdict, and the
verdict is about the wrong binary.**

That is the generator-family signature and it is why the priority is not lower:
*a red from a collision and a red from a real defect produce the same reading*,
and neither the log nor the report names the tree the binary came from. A green
from a collision is available too, if the two trees happen to agree.

The cost is not the lost run. It is that a collision-red sends someone bisecting
a defect that does not exist, and a collision-green retires a real one.

## The mechanism to fix it already exists, one line above the bug

Line 48 documents `TESTTMP=$$(mktemp -d)` as the way to get an isolated
directory. It is available, it is correct, and it is not the default. **A
documented trap is not a guard** — the comment tells you the hazard exists and
then leaves you in it unless you knew to opt out.

## Direction, not a prescription

The obvious shape is to default `TESTTMP` to something that cannot collide —
derived from the checkout path or a `mktemp -d` per invocation — rather than
requiring every caller to remember. Two things to weigh before doing that, and
they are why this is a direction and not a patch:

- **Something may depend on the shared path.** Cross-checkout reuse of a built
  artefact would be silently load-bearing today and would break loudly. Grep for
  hardcoded `/tmp/` consumers outside the Makefile first, including in the
  tooling, before changing the default.
- **An expected-output file must never contain an absolute `/tmp` path**,
  because testmgr rewrites those. If the default becomes a per-run directory,
  check that nothing bakes the old one into a recorded expectation.

## Ownership

`A+T` on the two-axes model: **A** is the file-lane (`Makefile`), **T** is the
work-tag (test-harness integrity). Same split as
`bug-t-a-silent-test-assertion-makes-the-harness-report-the-wrong-thing`, and
for the same reason — the subject is the harness, the file is A's.

**Sequencing note:** frankB holds `Makefile` for the 474-row assertion
conversion as of 2026-08-29. This ticket is a natural follow-on for whoever
holds that file next, but it must **not** be folded into that batch: a
mechanical conversion diff that also changes where every test writes its output
is no longer mechanical, and the one hunk that broke something becomes
invisible in it.

---

## 2026-08-29 — measured by Track T. The hazard is real but much narrower than
## filed, half of it is already closed, and **the proposed fix would break the
## harness.**

Taken as the ticket's own instruction — *"Grep for hardcoded `/tmp/` consumers
outside the Makefile first, including in the tooling, before changing the
default."* That grep is the whole content of this note, and it changes the
answer.

### 1. testmgr ALREADY privatizes every recipe-level `/tmp` path

```python
RUN_TMP = "/tmp/testmgr-scratch-%d" % os.getpid()
...
body = TMP_RE.sub(lambda m: m.group(0) if m.group(0) in pinned
                  else RUN_TMP + m.group(0)[len("/tmp"):], ln)
```

Per-PID, applied at execution to every recipe line. So the ticket's central
sentence —

> two suite runs on one box, in two different trees, write **the same absolute
> paths**

— **is not true of testmgr-driven runs**, which is how the watcher, `gate.sh`
and `testmgr --tier` all run. The rewrite exists precisely because two runs
"would interleave in each other's self-host chains and corrupt both (observed
2026-07-08: fixedpoint byte-diff with a clean tree)".

The exposure is **bare `make` invoked by hand**. That is a real hazard and worth
closing, but it is not six agent checkouts colliding continuously: CLAUDE.md's
per-fix loop is `make compiler/pascal26` plus a single repro, and the full
suites are refused outright by `.claude/hooks/no-full-suite.sh` for every lane
but T.

### 2. The recipe half was closed two weeks ago

[[chore-makefile-testtmp-parameterize]] landed 2026-08-14 (`b2cab6b6b`) and
routed the recipes through `$(TESTTMP)`. Its own closing note is exact: *"a
green gate here means the recipe half is closed, and nothing more."*

### 3. What is actually still open is the RUNTIME half — and it is already filed

60 distinct `/tmp` paths are baked into compiled sources across 37 files
(63 minus the 3 the Makefile also names, which are deliberately *pinned* so the
producer and consumer keep agreeing). Nothing rewrites a string constant inside
a binary, so **those do collide even under testmgr**. That is
[[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]], p35, and it is where
this ticket's real residual hazard lives.

`tools/testmgr_hardcoded_tmp_devtest.py` already guards against new ones, and is
RED today on exactly one new instance —
`test_nilpy_class_named_like_an_rtl_record.npy` writing
`/tmp/pxx_nilpy_rtlrec_probe.txt` — filed to Track N this morning.

### 4. THE PROPOSED DIRECTION WOULD BREAK TESTMGR, and testmgr says so in advance

This is the finding that matters. Four expressions in `make_dry_run()` hardcode
the literal `/tmp` prefix as it appears in `make -n` output, with this comment
sitting on them:

> That is safe today and must stay a deliberate choice: […] `$(TESTTMP)`, whose
> default is `/tmp` precisely so this keeps matching. **If anything ever runs
> `make_dry_run()` with `TESTTMP` set elsewhere, all four go blind AT ONCE and
> fail silently** — no privatization (concurrent runs collide again) and no
> producer/consumer merge (which is how `test-core#555/#556` went red on
> 2026-07-12). **Teach them the value before setting it; do not set it and
> hope.**

So defaulting `TESTTMP` to a `mktemp -d` — the ticket's stated direction — would
**remove the isolation that currently exists** and simultaneously break the
job-dependency merge, silently, in the direction where a red and a real defect
read identically. It would make the exact problem this ticket is about worse
while appearing to fix it.

The `/tmp` default is not an oversight. It is load-bearing, and the comment
above it is the guard.

### Recommendation

Not "change the default". The order is:

1. **Teach testmgr the value** — derive `TMP_RE`, the two `.so`/loader
   expressions and `RUN_TMP` from `TESTTMP` rather than a literal. Pure Track T,
   and it is the prerequisite the code names. Filed as
   [[chore-t-teach-testmgr-the-testtmp-value-before-anyone-changes-it]].
2. *Then* the Makefile one-liner becomes safe, and it is a small Track A change.
3. Separately, [[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]] is the
   half no default can fix.

Until step 1 lands, **the correct action on this ticket is to change nothing.**

### On the filing itself

The ticket was explicit that it was filed on its own merits and not asserted as
the cause of frankB's killed runs, and that restraint was right — the measured
answer is that it could not have been, for a testmgr-driven run. Recording that
because a candidate cause that is *ruled out* is worth as much as one confirmed,
and it is the half that usually goes unwritten.

---
track: A+T
prio: 55
type: bug
blocked-by: []
summary: "Makefile:49 is `TESTTMP ?= /tmp` — a fixed path, not per-checkout and not per-PID. Every agent's suite writes its test binaries to the same names in the same directory, so two concurrent runs on one box overwrite each other's artefacts. The failure mode is a wrong verdict, not a crash."
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

---
track: N
prio: 70
type: regression
status: done
---

# test-core RED: `test_nilpy_dataclass_dict_factory.npy`

- **Type:** regression (tstate NEW-RED) — **Track N**
- **Filed:** 2026-08-02 by the Track B agent, who noticed it in
  `twatch --status` while checking whether it was his own. It was not; the
  triage is below so whoever picks it up does not repeat it.

## What tstate says

```
open regression: test-core#src:test/test_nilpy_dataclass_dict_factory.npy
                 bad=2fbb5a270acc (4 in range)
```

## The flagged commit cannot be the cause

`2fbb5a270` is **tickets-only** — a single markdown file
(`bug-nilpy-class-attribute-unreachable-through-the-class-name.md`). It changes
no code at all, so the bisect has landed on an innocent commit inside its
range. Worth knowing before anyone reads it as the culprit.

## The range contains exactly one code change

| commit | what it touches |
| --- | --- |
| `ef73cf545` | **`fix(N): annotated class attributes parse and register`** — compiler |
| `42ac7bedc` | tickets only |
| `2fbb5a270` | tickets only |
| `d31a18713` | `lib/crtl` only (isatty, Track B) |

**`ef73cf545` is the only candidate**, and it is a plausible one on its face:
it changes class-attribute parsing and registration, which is precisely what a
`@dataclass` with a `field(default_factory=dict)` exercises.

## Measured, so the next person starts from facts

- The test **passes** against the **pinned stable** compiler and its output
  matches CPython byte for byte:
  ```
  F 1.5 1 because 7
  fresh per construction: 0 0
  ```
  So the failure is in compiler behaviour introduced after the pin — which is
  consistent with `ef73cf545` and rules out the `.npy` itself having rotted.
- test-core builds the compiler from HEAD rather than using the pinned binary,
  which is why a local run with `$(PXX_STABLE)` does **not** clear it. Anyone
  reproducing this must build a fixedpoint at HEAD first.

## Ruled out: the Track B commit in the range

`d31a18713` touches only `lib/crtl` (an `isatty` implementation). The same
session did widen `TPalFileStat` earlier, which would be the plausible way for
Track B work to reach NilPy — but `compiler/builtin` does **not** mirror that
record: `TPyStat` is its own class and `PyPalStat` issues its own syscall with
its own buffer. Checked, not assumed.

## Next step

Build a fixedpoint at `ef73cf545` and at its parent and run
`test_nilpy_dataclass_dict_factory.npy` against each. If it reproduces, the
class-attribute registration change is it; the ticket that commit belongs to
([[bug-nilpy-class-attribute-unreachable-through-the-class-name]]) is the place
to record the finding.


## Resolved 2026-08-02 — commit e1e9ea07a

The triage was right on every point: `2fbb5a270` is innocent, and `ef73cf545`
was the only code change in the range and was the cause. Mine.

That commit generalised the class-attribute branches in `PyRegisterClassMembers`
to match `name : ann = value` — which is precisely how a `@dataclass` field is
written. Those branches run BEFORE the `isDC` ones, so a dataclass's fields were
registered as ordinary class attributes and never reached the branches that
record their defaults into the `PyDc*` tables and build the generated ctor. Hence
the segfault, and hence a `field(default_factory=dict)` test being the one to
catch it.

Fix: the annotated shape is a PLAIN class's attribute only. A dataclass keeps the
pre-existing unannotated-only rule, so its behaviour is exactly what it was.

`test/test_nilpy_annotated_class_attribute.npy` now carries a `@dataclass` with
`str` / `float` / `default_factory=list` fields as a permanent control — the
interaction is pinned rather than remembered.

Gate: `gate.sh quick` GREEN, self-host fixedpoint byte-identical, both dataclass
tests green.

Filed by the Track B agent rather than by me; the range table saved the next
reader a bisect against a tickets-only commit.

## Log
- 2026-08-02 — resolved, commit e1e9ea07a.

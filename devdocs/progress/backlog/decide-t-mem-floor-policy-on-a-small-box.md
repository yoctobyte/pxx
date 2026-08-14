---
track: U
prio: 40
type: decide
summary: "MEM_FLOOR is an absolute 1500 MB, so any box with under ~1.75 GB available admits no job of any class — including a 2 GB machine, not just the 512 MB Pi. Two questions that should not be guessed: what the floor should be relative to, and whether a below-floor box should run at all or refuse loudly. The silence is fixed; the policy is not."
---

# Should a below-floor box run carefully, or refuse loudly?

- **Type:** decide — **Track U**. Split out of
  [[bug-t-mem-floor-is-a-fixed-1500mb-so-a-small-box-admits-nothing-ever]]
  on 2026-08-14, which fixed the half that is a bug regardless of the answer.
- **Not blocking anything today.** No box in the fleet is below the floor
  (plexus: 54.6 GB available, and memory is not the binding constraint there at
  all — it admits 38-212 concurrent by memory against a `hard_cap` of 24).

## What is already done

The **silence** was the real defect and it is fixed: `report_mem_floor()` runs
next to the startup banner and says, with numbers, when a box cannot admit its
own smallest job — naming the starvation path so the operator knows it is the
floor rather than a hang or a hardware fault. Nothing about the policy changed.

Worth noting what that surfaced: the threshold is **~1.75 GB available**, so a
**2 GB machine also admits nothing**. The ticket was filed about a 512 MB Pi;
nobody would guess a 2 GB box was affected, which is precisely why it had to be
printed rather than reasoned about.

## The fork

### 1. What should the floor be relative to?

```python
MEM_FLOOR = 1500 << 20            # today: absolute
mem_floor = min(MEM_FLOOR, int(MemTotal * SOME_FRACTION))   # proposed
```

The floor exists to leave the kernel and the rest of the box room to breathe,
and "enough" is not proportional in the same way at 512 MB as at 64 GB — a
fixed 25% is generous on a Pi and absurd on a workstation. **The fraction should
be measured on real small hardware, not picked because it looks reasonable.**
The user owns a 512 MB arm32 Pi, so this is measurable rather than theoretical.

### 2. Should a below-floor box run at all?

This is the part that is genuinely a judgement call, not an engineering one.

- **Admit carefully.** A Pi that can technically compile contributes coverage on
  an architecture nothing else in the fleet covers natively.
- **Refuse loudly.** A box that spends the run in reclaim produces slow,
  contended and possibly *wrong* timing data — and a watcher's output is
  verdicts other tracks trust. A wrong verdict is worse than no verdict, and
  "this box is too small, enrol it as a build-only oracle" may be the honest
  answer.

The second is really a question about what the fleet is *for*, which is why it
is here and not in Track T's queue.

## Recommendation

**Refuse loudly, with an explicit opt-in override.** The fleet's value is
trustworthy verdicts, and a box thrashing at one job per 90 s produces timing
data that looks like data. If the arm32 Pi is wanted for native coverage, enrol
it deliberately with a flag that says "I know this box is below the floor and I
want correctness-only results, not timings" — which also makes the limitation
visible in the tstate record rather than inferred later from odd numbers.

That said, this only matters once a small box is actually enrolled. Deciding it
in the abstract is cheaper than deciding it wrong, but leaving it open costs
nothing today.

## Gate

Whichever way: `tools/devtest_mem_floor.py` still green, and a below-floor box
either runs with a stated degraded mode or refuses with a reason — never the
current silent 90-second crawl, which is already fixed.

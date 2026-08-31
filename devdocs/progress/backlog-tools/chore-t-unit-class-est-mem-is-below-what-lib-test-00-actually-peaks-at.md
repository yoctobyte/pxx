---
track: T
prio: 25
type: chore
blocked-by: []
summary: "testmgr's own advisory, printed at the end of every full tier: `lib-test#00 peaked at 596 MB against a 550 MB estimate` for class `unit`. The scheduler admitted it on a promise the box did not have to keep. Raise the CLASSES row to max*1.5, or give the outlier its own class."
---

# The `unit` class `est_mem` is below what `lib-test#00` actually peaks at

Filed 2026-08-19 by Track T (plexus-T), from the tail of a green full tier —
`tools/testmgr.py --tier full`, 2742/2742 pass, c99f15692:

```
est_mem peak/est MB: conformance 42/256  corpus 261/400  qemu 53/256
                     selfhost 331/500  unit 596/550
!! est_mem TOO LOW for class unit: lib-test#00 peaked at 596 MB against a
   550 MB estimate — the scheduler admitted it on a promise the box did not
   have to keep. Raise the row (max*1.5) in CLASSES.
```

Every other class has headroom; `unit` is the one over, and by a single
outlier — `lib-test#00`, the target's build job that all ~167 `lib-test` jobs
carry as `deps:`. The consequence is admission-side only: memory-packing decides
what may start concurrently from `est_mem`, so an under-estimate lets one more
job in than the box can hold, and the loser is whatever gets killed under
pressure. Nothing observed to have gone wrong from it yet — filed because the
tool is asking, and the ask is currently ignored on every run.

**Do not simply raise the row to 596 x 1.5.** `unit` is ~1200 jobs of build-and-
run whose real footprint is tens of MB; the 550 MB row is already sized for the
pascal26 BSS rather than for the median job, and raising it further throttles
admission for the whole class to accommodate one dependency build. Weigh:

- give `lib-test#00` (and the equivalent per-target build jobs) their own class
  or an explicit per-job override — the outlier is structural, not statistical;
- or accept a smaller raise and let the learned metrics carry the rest, since a
  job with trusted metrics already uses `m["mem"] * 1.4` and ignores the class
  row entirely. The row only governs jobs with too few samples — which is
  exactly what a fresh box or a newly-split job is.

Related: [[feature-t-est-mem-from-measurement]] is why the learned path exists,
and [[bug-t-a-job-that-outgrows-its-class-can-never-pass-again]] is the same
shape on the OTHER class field — a class figure that is right for the typical
member and wrong for one, kept as though it were right for all.

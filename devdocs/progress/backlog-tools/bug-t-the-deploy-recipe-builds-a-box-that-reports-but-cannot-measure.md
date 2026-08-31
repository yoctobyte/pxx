---
track: T
prio: 50
type: bug
blocked-by: []
summary: "`trackt setup --fetch-corpus` provisions library_candidates/ only. It never runs, mentions or checks tools/install_externals.sh or tools/install_cross_sysroot.sh, so a box built strictly to track-t.md's documented deploy recipe comes up able to publish verdicts and unable to run ten of the jobs behind them. The corpus half self-announces as SKIP; the sysroot half goes RED, and a red is read as a defect in the tree — on seven's first full tier it auto-filed an 18-job cascade naming twelve innocent Rust commits."
status: open
owner: seven
---

# The deploy recipe builds a watcher that reports but cannot measure

Found 2026-08-29 on `seven`, enrolled that day and provisioned strictly per
track-t.md *"Deploy a watcher box"*:

```sh
git clone git@github.com:yoctobyte/pxx.git ~/trackt-watch \
  && ~/trackt-watch/trackt setup --fetch-corpus \
  && ~/trackt-watch/trackt start
```

That recipe completes, prints **`READY for --tier full`**, and the box begins
publishing tstate. It is nonetheless missing three separate provisioning steps
the full tier needs, and `trackt setup`'s own checklist does not have a row for
any of them.

## Measured, on the first completed full tier (3209 jobs, 959.2s)

| missing | jobs | how it presents |
| --- | --- | --- |
| `tools/install_cross_sysroot.sh` (qemu guest `ld.so` + libc, aarch64/arm32) and the i386 loader | 10 | **RED** |
| `tools/install_externals.sh` → `external/synapse` | 1 | SKIP |
| the uforth tree (`~/projects/uforth`) | 13 | SKIP |

The ten reds are the whole problem:

```
qemu-i386:    Could not open '/lib/ld-linux.so.2':         No such file or directory
qemu-aarch64: Could not open '/lib/ld-linux-aarch64.so.1': No such file or directory
```

`tools/run_target.sh` states the requirement in its own header — *"if a
dynamically linked test ever crosses an arch boundary it must add
`QEMU_LD_PREFIX` for the target's interpreter"* — and auto-sets it from
`~/.cache/pxx-cross/<arch>` **when a sysroot is present**. Nothing in the deploy
path ever creates one.

## Why the two halves are not the same bug

A SKIP is a known unknown: it announces itself, `testmgr` prints a loud
CORPUS MISSING banner with the exact fix, and track-t.md already has a section on
treating it as a finding rather than a green.

**A missing sysroot produces a RED, and a red is an accusation.** The jobs did
not fail; they never executed. But nothing downstream can tell those apart, so
`autoticket` did what it is supposed to do with eighteen simultaneous reds and
filed `regression-cascade-154d1aa3fba6`, naming **twelve Rust commits** as
suspects for a cause that was entirely local to the box. Triaged in `8a3ffca22`;
zero of the eighteen were attributable to the range.

This is the *"green on dev, red on the watcher ⇒ suspect HOST COUPLING first"*
rule arriving one layer too late to help: by the time a human reads that advice,
a ticket already exists with a commit range in it.

## Why this survived the ticket that was supposed to fix it

`done/bug-b-lib-test-unrunnable-in-a-fresh-clone-no-synapse-fetch` (frank3,
2026-08-17) found synapse missing in a fresh clone and fixed it by writing
`tools/install_externals.sh`. That is a correct and complete fix **for a dev
checkout**, which was the reported case. The watcher deploy path is a second
consumer of the same dependency and was never updated, so the fetcher has existed
since 2026-08-17 while the box that most needs it still does not call it.

The boundary, not the result, is what went unchecked — the same shape track-t.md
records under *"a coverage claim needs its BOUNDARY checked"*.

## Fix

1. `tools/twatch-setup.sh --fetch-corpus` runs `install_externals.sh` and
   `install_cross_sysroot.sh` alongside `install_lib_candidates.sh`.
2. `trackt setup`'s readiness checklist grows rows for `external/synapse`,
   `~/.cache/pxx-cross/{aarch64,arm32}`, `/lib/ld-linux.so.2` and the uforth
   tree — **absent must not print `READY for --tier full`**. The checklist is the
   artifact that told this box it was ready; it is the right place for the guard.
3. Prefer making the ten jobs SKIP rather than RED when the sysroot is absent,
   on the same argument as the corpus guard: an absent prerequisite is a known
   unknown, and only a red should ever reach a commit range.

Point 3 is the one worth arguing about, and it is the reason this is filed as a
bug rather than a chore. Everything else here is a checklist that is one row
short; point 3 is the property that made a checklist omission cost an innocent
accusation.

## Verified on seven

All three provisioned by hand 2026-08-29; native red count fell 15 -> 7, the
remainder being `test_hw_random_intrinsics` (this box is a Xeon E5645 with no
RDRAND — a permanent host-capability exclusion, filed separately) and known
pre-existing regressions. Full-tier confirmation of the ten cross-target jobs is
pending the next completed sweep and is NOT yet claimed here.

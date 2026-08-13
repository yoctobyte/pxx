---
summary: "pasmith: generate multi-UNIT programs — the last structurally unreachable bug class"
type: feature
prio: 55
---

# pasmith: multi-unit programs

- **Type:** feature (Track T — the tool). Findings file into the owning lane as always.
- **Status:** done
- **Opened:** 2026-07-14, split out of [[feature-pasmith-widen-grammar]] when the rest of
  that widening landed.

## Why

Every other rung on the widening list is in ([[feature-pasmith-widen-grammar]]): records
+ forward pointers, enums/sets, arrays, `string[N]`, exception hierarchies, parameter
modes, OOP, ansistring. **Multi-unit is the one gap left, and it is a structural one** —
several of the worst bugs we have shipped were unit-ORDER dependent and simply cannot be
expressed by a single-file generator:

- exception class matching across units — `on E: T` missed a descendant declared in a
  *later* unit (b339);
- symbol resolution / import bugs, where the defect only appears when the importer is
  large or the import order changes;
- initialization-section ordering.

## Shape

Emit N units plus a program: each unit declares types (records, enums, exception
classes), some of them referring to types from earlier units; each exports procedures and
functions; the program uses them in a random order. The checksum discipline is unchanged
(one number out), so the oracle machinery needs nothing new.

The real work is in the **driver**, not the generator: `tools/pasmith_run.py` currently
compiles one file. It has to write a unit set to a directory, put that directory on both
compilers' unit paths (`fpc -Fu`, `pxx -Fu`) and compile the program against it — and the
seed must still reproduce the whole set byte-for-byte.

## Acceptance

`pasmith --seed N --units 3` emits a program plus 3 units that FPC accepts (the
generator's contract), the driver compiles and runs the set under every oracle, and a
divergence still names its statement via the trace diff. One bounded run logged here,
clean or not.

## Done — 2026-08-13

`tools/pasmith.py --seed N --units K --outdir DIR` emits a support unit, K units
and a program; `tools/pasmith_run.py --units K` drives them through every
oracle. The single-file path is untouched — `--units` is a MODE, not a rung.

### Shape, and why it is this shape

The three bug classes this ticket names are all about ORDER, and the third one
(initialization sections) is the one that could easily have been tested
unsoundly. Pascal initialises a unit's DEPENDENCIES first, and only then follows
the uses clause. So the units are emitted as a **chain** — unit k uses unit k-1
— which pins the true order to u0, u1, ... uK-1, and the program's uses clause is
then **shuffled from the seed**. A compiler that initialises in uses-clause order
rather than dependency order produces a different order log and diverges; a
compiler that gets it right cannot be made to differ by the shuffle. That keeps
the rung inside the generator's contract: well-defined programs only, no
implementation-defined ordering to produce divergences that are nobody's bug.

Per unit k: an exception class `EUk` descending from `EUk-1` **in an earlier
unit** (the b339 shape with a unit boundary through the middle), a record whose
field type comes from unit k-1 (a layout that cannot be computed without
resolving across the boundary), an enum, exported functions folded into the
checksum, and an initialization section that reads unit k-1's initialised global
and calls `Note(k)` on a shared support unit every unit depends on — so the
order log is complete by construction.

The program raises `EUk` and catches it on `EUj`, j<=k chosen by seed: a
descendant caught on a base declared in a different, earlier unit.

Checksum discipline unchanged — one number out — so the oracle machinery needed
nothing new.

### Driver

As predicted, the work was in the driver, and it came to less than expected
because the shapes converge: both a single file and a unit set end up as "a .pas
to compile with its directory on the unit path".

- `evaluate()` puts the program's own directory on both compilers' unit paths
  (`-Fu`) **unconditionally**. Inert for single-file runs, and a unit path that
  depends on a mode is a way for the two modes to diverge for a reason that is
  not a bug. FPC additionally gets `-FU<per-oracle objdir>` so `fpc-O0` cannot
  link against units `fpc-O2` compiled.
- `generate()` writes either shape and returns the path to compile.
- `localize()` re-emits the whole SET in trace mode into its own directory — a
  traced program linked against untraced units would compile and mislead.
- The program header carries `gen-args: --units K`, so `gen_args_of()` rebuilds
  the identical subject. Without it localize() would have regenerated the seed as
  a single file — a different program that does not diverge, which is exactly the
  failure [[bug-t-pasmith-order-dependent-programs]] records.

### Acceptance

- **FPC accepts the set** (the generator's contract): 120 seeds, zero
  `fpc-reject`.
- **Every oracle compiles and runs it**: `fpc-O0, fpc-O2, pxx-O0, pxx-O2, pxx-O3`.
- **A divergence still names its statement**: the traced program emits
  `{ checkpoint N kind=K }` markers in the same contract the single-file
  generator uses, so `checkpoint_kinds()`/`localize()` work unchanged. Verified:
  14 checkpoints parsed, kinds `unitfn unitvar unitrec ... unitexc unitord
  unitordlog`, 15 trace lines out. A finding would therefore sign as e.g.
  `pxx-vs-fpc_unitexc` — the bug class straight out of the kind.

### The bounded run, as asked: CLEAN

```
pasmith_run: 120 programs, 0 divergences
             (0 = FPC-rejected/generator bugs, 0 = known signatures, 0 = NEW)
             oracles=[fpc-O0, fpc-O2, pxx-O0, pxx-O2, pxx-O3]
```

600 compile-and-run pairs, no divergence. pxx agrees with FPC on cross-unit
exception matching, cross-unit record layout, and initialization order for every
seed tried.

**Read that with the right amount of confidence.** A clean run means either pxx
handles these shapes, or the generated diversity is too narrow to have found
anything — and the set IS narrow by design: the per-unit shape is fixed, and
only the constants, the enum values and the catch level vary by seed. What is
now in place is the *structure* (units, the dependency chain, the driver, the
trace contract); widening what lives inside each unit is the cheap part and the
obvious next step for anyone who wants this rung to earn more.

Single-file regression check: `--seeds 1-6 --wide` produces byte-identical
output before and after this change (3 divergences, same signatures), confirmed
against the committed version.

## Log
- 2026-08-13 — resolved, commit 3c17cfc46.

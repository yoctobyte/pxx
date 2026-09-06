---
track: T
prio: 55
type: regression
blocked-by: []
status: backlog
found: 2026-09-06
found-by: frank-coordinator
owner: ""
summary: "The oldest open cascade on seven -- 18 jobs, bad `154d1aa3fba6`, last good `e417731e9007`, open since 2026-08-29 -- is the only one of three with NO ticket, and its range cannot explain its jobs. Nine of the twelve commits in range touch buildable files and ALL NINE are the Rust frontend (`compiler/rparser.inc` + Makefile + Rust test rows); the 18 failing jobs are cross-target extern-C rows on i386/arm32/aarch64, an xtensa object row, sqlite-threads-aarch64, two lib rows, three NilPy rows and `tools-devtest#00`. `rparser.inc` is on none of their paths and the only shared file in the range is the Makefile. So either a Makefile hunk broke a shared recipe path, or the cascade is not attributable to the range at all. FIRST ACTION IS A RE-RUN, NOT A BISECT: one of the 18 jobs at HEAD settles it in one measurement. Lane is a FALLBACK -- if the cascade is real the defect is Track A's or B's, and nothing here says it is T's."
---

# The 8-day cascade nobody has a ticket for

## What is measured

```
CASCADE 18 jobs (seven)   bad 154d1aa3fba6   last good e417731e9007   12 commits in range
  bad   2026-08-29 18:34  roster+ticket(A): T handover closed, and face twenty-six
  good  2026-08-29 18:27  docs(progress): fill the resolve sha sync.sh did not
  origin has advanced 6220 commits since
```

**Three cascades are open on seven and this is the only one with no ticket.** The other two
have `devdocs/progress/backlog/regression-cascade-b8e3b3010249.md` and
`regression-cascade-6758c7ce7dbd.md`. This one has been open **eight days**.

## The range cannot explain the jobs, and that is the finding

Nine of the twelve commits in range touch buildable files. **All nine are the Rust
frontend** -- `compiler/rparser.inc`, the Makefile, and Rust test rows:

```
8fb3f776c  feat(rust): Option<T> as a monomorphized generic enum
f20746561  merge: master into the rust topic branch          (Makefile only)
2efff6df5  feat(rust): Option<T> through fn signatures and returns
68dac6d2a  feat(rust): expression scrutinees, `if let`, unwrap_or
1ede0ffad  feat(rust): fixed-array struct fields
e4cbaf85d  fix(rust): `&`/`&mut` parameters must alias the caller
557df36d5  feat(rust): aggregate literals in return position
c59aab128  merge: master into the rust topic branch          (Makefile only)
fcfe1cba1  feat(rust): the engine's own idioms compile
```

**The 18 failing jobs contain no Rust.** They are:

| group | jobs |
| --- | --- |
| cross-target extern C | `test_cdecl_indirect`, `test_extern_c`, `test_extern_c_float` on **i386, arm32 and aarch64** -- the same three rows on three targets |
| other cross | `test-aarch64#test_parallel_reduction`, `test-emit-obj#cxtensa_obj.c`, `test-sqlite-threads-aarch64#compiler/.pascal26.fixedpoint` |
| NilPy | `examples/tk/tkinter_facade.npy`, `test_nilpy_parent_call_after_instantiation.npy`, `test_nilpy_startswith_tuple.npy` |
| lib | `lib_inttohex.pas@2`, `test_dynlib.pas` |
| tools | `tools-devtest#00` |

`compiler/rparser.inc` is the Rust parser. **It is not on the path of any of those**, and
the only file the range touches that they could conceivably share is the Makefile.

## Two readings, and the discriminator is one re-run

1. **A Makefile hunk in the range broke a shared recipe path.** Testable by reading the nine
   Makefile hunks; they are small and mostly wire new Rust rows.
2. **The cascade is not attributable to the range at all.** Every one of those job families
   is cross-target or environment-dependent, and the cross targets run under **qemu**. A
   qemu or toolchain event on seven at 18:30 on 2026-08-29 would take exactly this set and
   leave the native rows alone. Circumstantially, `038c3acf1 fix(T): install_qemu.sh died on
   26.04 -- qemu-user-static is virtual` sits in a *later* range, so qemu on these hosts has
   been provably fragile in this window.

**This ticket does NOT claim reading 2.** It claims reading 1 needs a Makefile mechanism
nobody has named, and that **the cheapest next step is a measurement rather than a
narrowing**: run ONE of the 18 jobs at HEAD.

- If it **passes**, the cascade is stale, and the question becomes why 18 rows stayed `fail`
  in the persisted state for eight days -- a `twatch.py` question, genuinely Track T's.
  `twatch.py`'s own comment says a cascade entry names no single job and stays open while
  any swept job is still `fail` in the persisted state, deliberately, because closing one on
  a single clean run bit the fleet on 2026-07-20/21.
- If it **fails**, the cascade is real, the range is wrong or incomplete, and it belongs to
  whichever lane the failing row names. **Do not re-lane it on this ticket's word.**

## Why the lane here is a fallback and says nothing

Filed `track: T` because **the first action is an instrument**, not because the defect is
T's. Three of the failing rows are NilPy, six are cross-target codegen, two are lib. If the
cascade is real this is Track A's and possibly Track B's. The banner every auto-filed
regression carries applies to this hand-written one too: *guessing a lane from the failing
step is what sent three reds in one job to the wrong lane.*

## What I did not do

I ran no tier -- this seat does not, and the full tier is behind the no-full-suite hook,
which I have not lifted and would not lift for a question that is not mine to answer. Every
fact above is `git log`, `git rev-list` and `git show --name-only` over the recorded range,
plus the job list from `devdocs/progress/tstate/TSTATE.md`. **The ranges themselves are the
watcher's: I have not verified that `e417731e9007` was ever green for these jobs, only that
TSTATE records it as the last good.**

---
slug: bug-t-a-present-corpus-is-never-checked-against-its-pinned-commit
track: T
prio: 45
status: rejected
owner: unassigned
---

# T: `present()` compares existence, not the commit the corpus was pinned to

## The alarming version is FALSE — say that first

Raised by frank-rust as a provenance hole: *"three copies of the corpus on this
box, `-Fu` pointing at a sibling lane's tree, a measurement whose input nobody
names."* Reasonable from where it stood, and **measured wrong.** Every layer it
could not see turns out to exist:

| worry | reality |
| --- | --- |
| nothing versions the corpus | `tools/install_lib_candidates.sh` is **tracked** and pins every fetch — `FPC_COMMIT="0d122c49534b480be9284c21bd60b53d99904346"` (release_3_2_2) for rtl-generics, `LUA_SHA256`, `ZLIB_COMMIT`, ~20 more |
| the copies could drift | each fetched tree carries a **`PROVENANCE.md`** naming its commit |
| they might already have drifted | all three rtl-generics copies stamp the **same** commit; frank-rust separately measured `generics.collections.pas` byte-identical (`sha256 5a3402725ab53181`) across them — **two independent mechanisms agreeing, with no shared upstream** |
| "three copies" | **four** — `~/pxx` (9 corpora), `~/frankB` (5), `~/frankA` (2), `~/trackt-watch` (20). They differ in *which* corpora are installed, not in version |

## The narrow version is TRUE, and it is this ticket

`present()` (`tools/install_lib_candidates.sh:114-116`) is:

```sh
present() {  # $1 = subdir; true if a non-empty tree already exists and not FORCE
  [ "$FORCE" != "1" ] && [ -d "$DEST/$1" ] && [ -n "$(ls -A "$DEST/$1" 2>/dev/null)" ]
}
```

**It asks whether a directory is non-empty. It never reads the `PROVENANCE.md`
that the same script wrote.** So when a `*_COMMIT` is bumped, every existing copy
silently keeps the old tree and reports `present (FORCE=1 to re-fetch) — skip`,
which reads as *up to date*. The stamp and the pin then disagree, and **nothing in
the repo compares them** — the one artefact that would catch it is written by this
script and read by nobody.

The failure is quiet in the direction that matters: a lane measures a corpus line
number, cites the pinned commit because that is what the installer says, and the
tree on disk is an older one. Line numbers are exactly the kind of figure a stale
corpus changes.

## Fix

Have `present()` (or the caller) compare the stamped `Commit:` against the
variable and re-fetch on mismatch — the data is already on disk in the format
needed. Print the stamped commit in the `skip` line so a human sees which tree was
used. **Add a `--verify` mode** that checks every installed corpus against its pin
and exits non-zero, so it can be a gate step rather than a habit.

**Do not make a mismatch fatal by default** — a lane deliberately holding an older
corpus to reproduce an old figure is legitimate, and turning that into a hard stop
during a bisect is worse than the bug.

## Provenance of this ticket

Filed by the coordinator, 2026-08-30, during the pre-merge pause — recorded rather
than fixed, because the fleet is stopped for a re-pin and this is not in the pin
path. Found while checking a flag from frank-rust, which was **worth raising and
wrong in its strong form**; the check that settled it cost four commands and is
written above so the next person does not re-run them.

## Rejected 2026-09-02 — the Track T tooling backlog was cut as a pile

Owner decision, not a judgement on this ticket individually. 73 of the 74 open
`track: T` tickets were filed between 2026-08-31 and 2026-09-02, 58 on one day.
The pile was too large to work through, and a ticket nobody will fix does not sit
neutrally: it stays in the ranker forever at zero value, which is the same
argument CLAUDE.md already makes for `rejected/` over a low prio.

Four were kept, on a purely structural test — an active umbrella, or a hard
`blocked-by:` edge from live non-T work: `umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**This is a reversible archive, not a deletion.** If one of these is refiled
later, it should be refiled with the evidence that makes it worth doing rather
than restored wholesale.

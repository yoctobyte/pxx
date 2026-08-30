---
slug: grant-elf-writer-and-object-writers-to-b4
track: A
prio: 50
type: grant
blocked-by: []
status: backlog
owner: frank-optimize-b4
found: 2026-08-30
found-by: frank-coordinator
summary: "frankA holds Track A. frank-optimize-b4 keeps a bounded file slice under A's gate: compiler/elfwriter.inc, defs.inc's ELF constants, and the object writers (writeELFRelX64 / writeELF32Rel). Dispatched by ticket, not by lane. Disjoint from symtab.inc and every frontend."
---

# Grant: the ELF writer and the object writers, to frank-optimize-b4

**Track A belongs to frankA.** Two sessions had been holding the letter
unguarded — the exact collision the lane letters exist to prevent. b4 proposed
the split and its argument settled it: *splitting a lane down the middle is worse
than either of us holding it whole*, and frankA has `symtab.inc` live and
half-landed plus the two `regression-test-asm-*` items.

## Scope

- `compiler/elfwriter.inc`
- the **ELF constants** in `compiler/defs.inc`
- the object writers — `writeELFRelX64` (the `.asm` frontend's) and
  `writeELF32Rel`

Nothing else in `compiler/**`. **Not** `symtab.inc`, not `ir*.inc`, not any
frontend. A change outside the slice is a Track A ticket, filed and handed to
frankA like any other lane's escape.

## Why a slice and not a letter

This is not a new lane and must not become one. It is a **bounded file grant
under Track A's gate** — same shape as the xtensa cleanup grants — because it
happens to be a coherent slice: it is where b4 has spent the night
(`75d2ba662`, `df98fea47`, `3b8d1039e`, `1befc225d`), where its remaining filed
tickets live (`feature-a-a-general-x86-64-relocatable-object-writer`, and
`ELF_AARCH64_PAGE` if the owner takes the page-size question back), and it does
not touch the files frankA is in.

## Gate

Track A's, unchanged: `make compiler/pascal26` (which IS the byte-identical
self-host fixedpoint) plus the repro, and `python3 tools/forwardlint.py` clean
before the push. `gate.sh quick` before a pin, which b4 does not run — pins are
the coordinator's.

## Why this is filed rather than agreed in a message

b4's own note: *"I would have taken a message as sufficient."* An authorisation
is a finding about what is permitted, and **an unfiled grant does not read as
missing — it reads as covered**, because a neighbouring ticket covers the same
file. The tooling makes an unfiled ticket unrepresentable and cannot see an
unfiled grant.

## Release condition

When b4's session ends, or when frankA needs the slice. An open grant on shared
files reads as a standing exception to anyone greping for who may edit
`elfwriter.inc`, so **release it rather than leave it** — the way
`grant-compiler-pas-c-branch-tok-unbounded-to-frankc` was released unused the
same day.


---

## LAPSED BY ABSENCE, 2026-08-30 ~14:4x — the holder is not running

Found by the coordinator running `ls devdocs/progress/backlog/grant-*`, the enumeration
procedure adopted today after two release sweeps worked from memory instead.

**`frank-optimize-b4` is not a live session.** It does not appear in the fleet listing; the
live sibling is `frank-optimize`, a different session under a different name. So this grant
has **no holder**, and a lock with no holder is strictly worse than no lock — it reserves a
file against agents who would otherwise be dispatched to it, and it does so invisibly to the
ranker.

**The file slice is released:** `compiler/elfwriter.inc`, `defs.inc`'s ELF constants, and the
object writers (`writeELFRelX64` / `writeELF32Rel`) are unheld as of now.

### What is NOT being claimed here

**This is a lapse, not a resolution.** Nothing in this annotation says b4's work finished.
The last `elfwriter.inc` commit is `d147202a1` ("DbgBuf grows on demand — `-g` was 1.5% from
failing at EVERY `-O` level"), which is *consistent* with the slice having completed and
equally consistent with it having stopped partway. **A grant is a lock; releasing a lock and
closing the work are different acts**, and conflating them is how a half-done slice gets
recorded as done. If b4's ticket is unfinished, it is unfinished under whoever picks it up.

Whoever resumes that slice re-claims it and re-requests the files. Do not treat this
annotation as authorisation.

### The overlap that made this urgent rather than tidy

`defs.inc` is **currently granted to frankwasm** for the UTF-16 type kinds. That is disjoint
in practice — type kinds are not ELF constants — but the board recorded two live holders of
one file, and nobody looking at the board could tell that the overlap was harmless. Same
failure as this ticket's own section 2 correction: **the visible record contradicted the
dispatch, and the visible record is what anyone else would check.**

### The lesson, third instance today

Filing a grant makes it enumerable; it does not make it current, and it does not notice when
its **holder** disappears. Sessions end; grants do not. There is no aperture for either
condition — `check` has STALE-PARK for prose park conditions and nothing at all for grants.
Candidate T ticket: a `GRANT-NO-HOLDER` / `GRANT-STALE` aperture keyed on the `owner:` field
against the live session list, which is the one thing a human coordinator cannot hold in
their head across a day.

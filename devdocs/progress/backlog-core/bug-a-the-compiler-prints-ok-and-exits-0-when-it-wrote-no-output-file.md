---
track: A
prio: 60
type: bug
status: backlog
found: 2026-09-06
found-by: frankZ
owner: ""
blocked-by: []
summary: "`pascal26 src.pas /nonexistent-dir/out` prints `ok: /nonexistent-dir/out [code=245528B data=6276B bss=52108B procs=650]` and exits 0, having written nothing. The success verb, the byte counts and the exit status are all produced from the in-memory image and none of them is checked against the artefact reaching the disk, so the one instrument every harness and every agent uses to decide a build happened cannot distinguish a build from a build that went nowhere. Measured at ac64b5aec (pascal26 26b8b0adf44256db, srchash 3d33dc942f7869b3 matching the tree). Cost the finder a false regression reading the same hour: a reaped scratch directory turned every compile into a silent no-op while still printing ok:, and the missing binary then read as `test_promoint_bitwise` failing. This is CLAUDE.md's 'every instrument that lies, lies by being CORRECT ABOUT SOMETHING ELSE' in the one place the file tells everyone to trust — the ok: line carries a sha-adjacent authority it has not earned."
---

# The compiler prints `ok:` and exits 0 when it wrote no output file

## Measured

    $ ./compiler/pascal26 test/test_promoint_bitwise.pas /nonexistent-dir-xyz/out
    ok: /nonexistent-dir-xyz/out  [code=245528B  data=6276B  bss=52108B  procs=650]
    $ echo $?
    0
    $ ls /nonexistent-dir-xyz/out
    ls: cannot access ...: No such file or directory

At `ac64b5aec`, `compiler/pascal26` = `26b8b0adf44256db`, srchash
`3d33dc942f7869b3` matching the tree, real `converged after 2 round(s)`.

## Why it matters more than a missing errno check

**Three signals agree and all three are computed before the write.** The verb,
the four byte counts and the exit status are all read off the in-memory image.
Nothing compares them to a file on disk, so they are jointly incapable of
noticing that the write did not happen. A caller that checks `rc`, greps for
`ok:`, or parses `code=` — which is every caller — gets the same wrong answer
three ways, and CLAUDE.md's rule that a second source only counts if it FAILS
DIFFERENTLY is violated by construction here: these are one reading wearing
three faces.

## The measured cost, same hour, by the finder

A reaped scratch directory turned every compile into a silent no-op that still
printed `ok:`. The absent binary then presented as `test_promoint_bitwise`
failing — a real job in that night's report — and the first reading was "a
live regression". It was not; the row had been FIXED at that very sha. The
false trail cost a rebuild and a bisect-shaped detour, and the thing that ended
it was `bash` saying *No such file or directory* for a path the compiler had
just called `ok`.

**The harness is exposed the same way and does not know it.** `$(TESTTMP)`
exists today, so no row fails; a recipe whose output directory is missing gets
`ok:` and a green compile step, and only fails later at a comparison, naming
the wrong thing.

## Fix

Assert the artefact after writing it, and make the success verb depend on it:
`stat` the output path, require a nonzero size, and fail loudly if the open or
the write returned an error. **The positive control is free and must be in the
same commit** — a build to a path under a directory that does not exist must
be REJECTED, asserted, or this ticket's own fix cannot be shown to work.

Related: `bug-t-the-job-map-cannot-be-asked-whether-a-given-source-was-exercised`
is the same family one level up — an instrument that answers a different
question without erroring.

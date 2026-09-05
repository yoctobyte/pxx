---
slug: bug-t-the-c-conformance-corpus-is-absent-from-this-checkout-so-make-test-c-covers-less-than-its-name
title: "The c-testsuite corpus is gitignored and therefore PER-CHECKOUT: absent in frankA and frankB, so `make test-c` there silently drops its conformance half"
track: T
prio: 25
type: bug
status: open
created: 2026-09-03
found-by: frankB
owner:
blocked-by:
summary: "In the frankA and frankB checkouts `library_candidates/c-testsuite/tests/single-exec` does not exist, so `make test-c-conformance` and all four cross rows SKIP and `make test-c` delivers only its test-core half. THE CORPUS IS GITIGNORED, SO ITS PRESENCE IS PER-CHECKOUT AND NOT A PROPERTY OF THE BOX OR THE HARNESS -- it is present in 6 of 24 checkouts under /home/neo including trackt-watch, and seven publishes all 30 test-c-conformance jobs PASS at its most recent full tier (0975f200bd17, 2026-09-03 12:57Z), which is stronger evidence than any directory listing because a job cannot pass without its corpus. NOTHING HAS BEEN UNCOVERED FOR ANY PERIOD; this ticket was first filed claiming exactly that and the claim was false. What is real and left: a Track C worker in one of those checkouts who runs the documented gate gets less than it says. Fix is `tools/install_lib_candidates.sh c-testsuite` in the affected checkout, a network fetch, hence not an agent's call. The MISLEADING part is already fixed in 72c431bd9: `test-c-conformance-cross` printed `all targets green` over four skips and `test-c` printed `c-conformance green`, and both now branch on the suite directory and say NOTHING MEASURED / SKIPPED."
---

# What is true, and how the first version of this ticket got it wrong

Filed 2026-09-03 as *"the C conformance battery is skipping entirely because its
corpus is not installed"*, escalated as a coverage hole needing a network fetch,
and **the premise was false**. Corrected within the hour by frankuser and
franka-29 (`2f58b23be`, `addffd260`), and the correction is the useful part.

| claim | status |
| --- | --- |
| the battery SKIPs in this checkout | true, measured |
| ⇒ the battery has measured nothing for an unknown period | **false** |
| ⇒ it is a fleet coverage hole for the owner | **false, retracted** |

seven publishes **all 30 `test-c-conformance` jobs as PASS**, `job_last_pass`
`0975f200bd17`, its most recent FULL tier (2026-09-03 12:57Z). A job cannot pass
without its corpus, so the battery runs at the current tip on the host that
produces the fleet's breadth.

**The discriminator cost one grep and was available BEFORE the escalation.** The
error was reading per-checkout state as a property of the harness: the corpus is
gitignored, so `ls` in one checkout answers about that checkout and nothing else.
Two independent sessions made the identical inference from the identical skip,
which is what makes it worth writing down rather than quietly deleting — the
observation was correct and only the scope of the conclusion was invented.

# What is actually left

Only this: **`make test-c` in frankA or frankB delivers its test-core half and
silently drops its conformance half.** That is a real cost to a Track C worker
following the documented gate in those trees, and it is one command to remove —
`tools/install_lib_candidates.sh c-testsuite`, a network fetch, so it belongs to
whoever owns the box rather than to an agent. p25 because the coverage it would
restore locally is already being produced on seven.

# The defect that WAS real is fixed and is not this ticket

`test-c-conformance-cross` printed `test-c-conformance-cross: all targets green`
unconditionally, over four rows that each printed SKIP, and `test-c` printed
`base gate + c-conformance green` the same way. **A summary line that cannot say
no**, and it is the reason a local skip read as a coverage hole to two sessions
in a row rather than to none. Both now branch on the suite directory
(`72c431bd9`). Same family as the `test-c-abi-glibc-oracle` rows twenty lines
above, which count what ran and go RED on a partial run; the difference is that a
missing gitignored corpus must not be a RED for everyone, so this one reports
honestly instead of failing.

## THE PASCAL SIBLING, MEASURED 2026-09-06 — same corpus root, same gitignore, wider spread

Found by looking for this ticket's sibling rather than by a census, which is the
cheaper search once a name exists.

`tools/run_pascal_conformance.sh:34` reads its corpus from
`$ROOT/library_candidates/fpc-testsuite/tests/test` — **the same gitignored root**
(`.gitignore:36`) as the C suite. Line 95:

```sh
if [ ! -d "$SUITE" ]; then
  echo "$LABEL: SKIP — no suite at $SUITE (run tools/install_lib_candidates.sh fpc-testsuite)"
  exit 0
fi
```

**The message is honest and names its own remedy** — this is the good version of
the RUNNER-ABSENT shape, not the silent one. **The residual is `exit 0`**, which
is only safe while something counts skips and something expects the count.

### The spread across 28 trees under `/home/neo`

| | trees |
| --- | --- |
| **can run it** — `fpc-testsuite/tests/test` present, 1447–1449 `.pp` | **6**: frank1, frankA, frank-optimize, frankZ, pxx, trackt-watch |
| **have `library_candidates/` but NOT the fpc suite** | **5**: frankB, frankC, frankD, frankS, frankwasm |
| **no `library_candidates/` at all** | **17** |

**The middle group is the trap.** Those five have the parent directory, so a
presence check written against `library_candidates/` passes and the corpus still
is not there — the same one-level-too-shallow error as checking a mount point
instead of a file.

### And the reassurance, stated deliberately so this is not read as an alarm

**`frankZ` and `trackt-watch` both have it.** So the tier and the three
`test-pascal-conformance` job lines worked on 2026-09-05/06 ran against a real
1447-program population. **Nothing green on that date is green by vacuum.** As
this ticket's own first version proves, the expensive error here is claiming a
coverage hole that is not there.

### One more thing that reads as an absence and is not

`test/pascal-conformance/` in the repo contains exactly one file, `pxx.skip` (168
lines), and **zero programs — by design.** It is the skip list; the corpus is the
gitignored root above. `test/c-conformance/` likewise holds five `pxx.skip*`
files and no `.c`. **A curated 168-line skip list sitting alone in a directory
reads as a populated suite that is mostly passing**, and one session did read the
empty directory as its missing population on 2026-09-06 while holding 1447
programs elsewhere on disk. Worth a line in each directory saying where the
corpus actually lives.

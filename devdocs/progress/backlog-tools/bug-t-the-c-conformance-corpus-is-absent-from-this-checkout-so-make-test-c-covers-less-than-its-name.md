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

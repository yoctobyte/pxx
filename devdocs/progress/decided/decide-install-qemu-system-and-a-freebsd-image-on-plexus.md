---
track: U
prio: 55
type: decide
blocked-by: []
summary: "APPROVED 2026-08-31 by the owner: install qemu-system and pull a FreeBSD image on plexus. 'this box is dedicated to development. i think we have plenty disk space left. so yes, we can pull a BSD image.' Verified at ruling time: plexus root filesystem 156G, 84G available (44% used), so a multi-GB image is comfortable. This unblocks the FreeBSD port work that had no bootable kernel to test against. Fleet context recorded the same day and NOT part of this approval: borg is being repaired this week, and seven is moving off-site to a work location because it is too noisy for the house -- so plexus is the box to build this on, not seven."
---

# May Track T install `qemu-system` and a FreeBSD image on plexus?

- **Type:** decision (Track U — the owner's machine).
- **Filed 2026-08-28 by Track T (pxx-a5)** after completing step 1 of
  [[feature-t-freebsd-image-and-runner]]. **This is a question, not a task
  someone forgot to do** — the work is understood and small; only the consent
  is missing.
- Unblocks: `feature-t-freebsd-image-and-runner` → `feature-port-freebsd-native`
  (top of Track A's ready queue, repeatedly picked up and put back down).

## Why you are being asked rather than told

**plexus is your workstation as well as the test box.** Installing a system
emulator and downloading a multi-gigabyte OS image changes its configuration and
its disk, which is different in kind from the test-infra work Track T normally
does on it unasked. The same instinct kept a 251s test sweep off the box earlier
at load 27; this is that instinct applied to packages and disk.

**Nothing has been installed, downloaded, created or booted.** Step 1 was
read-only.

## What was established first, so this is not a speculative ask

- There is **no FreeBSD image on this machine**, and the belief that one existed
  somewhere was a misreading — the phrase *"pre-built qcow2 exists"* in
  `feature-port-freebsd-native` is a statement about what **FreeBSD.org
  publishes**, filed as a contrast with OpenBSD's *"no pre-built qcow2"* in the
  same commit. Not stale, not about another box. That lead is closed.
- The real gap is narrow: **`qemu-user` is installed, `qemu-system` is not.**
  That is why the cross-target tiers work (foreign *binaries*, user-mode) and
  nothing here can boot a *kernel*.
- **Disk is a non-issue**: `/` has 96G free, `/data` has **2.0T**.

## What is actually being asked for

1. **A package**: `qemu-system-x86` (Ubuntu). Tens of MB plus dependencies.
2. **An image**: the official FreeBSD/amd64 qcow2 VM image from
   `download.freebsd.org`. *Exact size not stated here because it was not
   fetched* — the compressed VM images are in the hundreds-of-MB-to-low-GB
   range and expand to several GB. It would live under `/data`, not `/`.
3. **Running it**: a headless boot during the test job — RAM in the 1–2 GB
   range while running, nothing resident between runs.

## The three answers, any of which is useful

1. **Yes, go ahead** — Track T installs the package, fetches the image under
   `/data`, and writes the runner. The ticket resumes at its step 2.
2. **Not on plexus** — then say which box, or that the FreeBSD port waits for
   one. `feature-port-freebsd-native` moves from "blocked on infra" to "blocked
   on a machine", which is a truer label and stops it being re-picked.
3. **You install it yourself** — name where the image lands and Track T writes
   the runner around it. Fine, and arguably better: it keeps package changes on
   your side of the line entirely.

## Why it is prio 55 and not lower

Ranked to match what it blocks, not to its own size: it is the sole gate on the
Track T ticket that is the sole gate on the top Track A item. Per
[[decide-t-should-a-skip-close-an-open-regression]]'s note about decisions and
ranking, **a decision left unreached is an answer given by default** — and the
default here is "the FreeBSD port stays unstartable indefinitely", which is a
real outcome nobody has chosen.

## Not urgent

Nothing is broken and nothing regresses while this waits. It is ranked to be
*reached*, not to interrupt.

---

# APPROVED 2026-08-31 — install qemu-system, pull a FreeBSD image

Owner: *"yes this box is dedicated to development. i think we have plenty disk
space left. so yes, we can pull a BSD image."*

**Verified at ruling time rather than assumed:** plexus root filesystem is 156G
with **84G available** (44% used). A multi-GB OS image is comfortable.

This was the owner's call for the reasons the ticket gives — it costs disk, it
pulls a multi-GB image over the network, and installing a system emulator
changes the box for every lane. All three are his to spend.

## Build it on plexus, and this is now load-bearing

Two fleet facts the owner stated the same day, recorded here because they decide
*where* this goes and are recorded nowhere else:

- **borg** is being repaired this week.
- **seven** is moving off-site to a work location — it is too noisy to keep
  running at home.

So plexus is the host for the FreeBSD VM, not seven. Anything built assuming
seven stays reachable at home should be re-checked against that.

## Not approved here

Nothing about *what* the FreeBSD port must then pass. This clears the blocker —
that the port had no bootable kernel to test against — and no more.

*Approved 2026-08-31 by the owner; disk verified by frank-user.*

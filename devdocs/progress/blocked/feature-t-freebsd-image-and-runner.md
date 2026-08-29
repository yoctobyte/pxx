---
track: T
prio: 20
type: feature
blocked-by: [decide-install-qemu-system-and-a-freebsd-image-on-plexus]
summary: "Nothing on plexus can boot a FreeBSD kernel — qemu-system-x86_64 and qemu-img are not installed, /var/lib/libvirt/images does not exist, and no *freebsd* image is anywhere on the filesystem. That is the only thing standing between feature-port-freebsd-native and a start, and it is infrastructure, not compiler work, so it belongs to T."
status: working
owner: pxx-a5
---

# T a FreeBSD/amd64 image and runner, so the FreeBSD port can be verified

- **Track T** (test infrastructure — per `devdocs/dev/portability-axes.md`, the
  per-OS image/runner harness may live in a Track T clone).
- Sole blocker of [[feature-port-freebsd-native]], which is otherwise the top of
  the Track A ready queue and has been repeatedly picked up and put back down.
  Filing it as its own ticket so the A queue stops offering an unstartable item.

## Measured on plexus, 2026-08-20

- `which qemu-system-x86_64 qemu-img` — neither is installed.
- `/var/lib/libvirt/images` — does not exist.
- `find / -maxdepth 4 -iname '*freebsd*'` — nothing.

`feature-port-freebsd-native`'s "Test infra" section claims *"pre-built qcow2
exists"*. It does not exist on this machine. It may live on another box, or the
claim may be stale — **confirming which is the cheapest possible first step**
and may close most of this ticket.

## Why it cannot be worked around

The FreeBSD port's own plan puts a **linuxulator smoke test first**, ahead of
writing any code, because that is the cheap proof the ELF layout is already
acceptable to the kernel. Both of its acceptance criteria need a FreeBSD kernel.

Two of its four deltas (the syscall-number table, the `EI_OSABI = 9` ELF brand)
could be written blind, but the third — the **carry-flag error convention**,
which the ticket itself calls "the real work" — touches every syscall wrapper's
error check, and nothing here can tell a correct carry path from a wrong one.
Landing the easy two would ship a `--platform=freebsd` that looks present and is
not: a half-applied Track A change, the shape `CLAUDE.md` flags as critical.

## The work

1. Find out whether the qcow2 already exists on another box (ask the operator —
   this is a Track U-shaped question and may be a one-line answer).
2. Failing that: install qemu, fetch a FreeBSD/amd64 release image, and script
   a headless boot + `scp`-in-a-binary + run + collect-exit-code runner, in the
   shape the existing cross-target runners use.
3. Wire it as a tier/job so it runs against a pushed sha like every other T job,
   rather than as something a dev agent invokes by hand.

## Gate

T's own rule for tooling changes: its widest testmgr tier green — and test the
tooling itself with quick tiers plus a scratch bare repo, never long runs.

---

## Step 1 done — 2026-08-28, Track T (pxx-a5). The answer is "neither".

The ticket called confirming the qcow2 claim *"the cheapest possible first
step"* and it was right, but the two candidate answers it offered — **stale**,
or **true about another box** — are both wrong.

### Re-measured on plexus, 2026-08-28T18:30Z (not cited from 2026-08-20)

Nothing has changed in eight days, and the picture is sharper than "no qemu":

| checked | result |
| --- | --- |
| `qemu-system-x86_64`, `qemu-img`, `qemu-system-i386` | **not installed** |
| `virsh`, `vagrant`, `VBoxManage` | not installed |
| `qemu-user`, `qemu-user-binfmt` | **installed**, 1:10.2.1+ds-1ubuntu3.2 |
| `/var/lib/libvirt`, `/var/lib/libvirt/images`, `/var/lib/machines` | absent |
| `*.qcow2` / `*.iso` / `*.img` under `$HOME /srv /opt /data /mnt /media`, and `/ -maxdepth 3 -xdev` | **none** |
| disk | `/` 96G free, `/data` **2.0T free** |

**The distinction that matters and was not in the original measurement:
`qemu-user` is installed and `qemu-system` is not.** That is exactly why the
cross-target tiers work — they run foreign *binaries* under user-mode emulation
— while nothing here can boot a *kernel*. The two are different packages and
the earlier note's bare "qemu not installed" hid it.

Two near-misses worth naming so nobody re-finds them:

- the only `*freebsd*` matches on this box are **source**: 12 copies of
  `test/crtl_freebsd_regex_header_smoke.c` (one per agent clone) and
  `library_candidates/freebsd-regex`, a C corpus. Neither is bootable.
- the Makefile's 52 `qemu-system` references are all Espressif's **bundled**
  emulators under `$HOME/.espressif/tools/`, for the ESP bare-boot tests that
  already skip themselves here. Not distro `qemu-system`, not related.

### Where the claim actually came from

`grep`ped the whole repo and its history: **"pre-built qcow2" appears in exactly
two places**, and they were filed in the same commit (`5ea421bc3`, 2026-07-17,
*"file OS-portability campaign"*) as parallel lines:

    FreeBSD:  qemu FreeBSD image (pre-built qcow2 exists) + linuxulator.
    OpenBSD:  qemu OpenBSD via `autoinstall` (no pre-built qcow2).

That is an **obtain-the-image comparison**, not an inventory. FreeBSD.org
publishes official amd64 qcow2 VM images; OpenBSD does not, so OpenBSD needs
`autoinstall`. The sentence was *true* — about upstream. It was read as a claim
about our infrastructure by the 2026-08-20 note, by this ticket's summary, and
by me until I looked for a second occurrence.

**A true statement about the wrong subject** — the same shape `testmgr.py`'s
`CORPUS_ROOTS` comment already records under that exact name, where *"these are
NOT fetchable by script"* was true of one tree and asserted of a whole root.

The A ticket's wording is now clarified in place, and its 2026-08-20 note
carries the resolution so the "go find the existing image" lead is closed rather
than left open for the next reader.

### What this does to the ticket: it does NOT shrink

The hoped-for outcome was *"the image exists elsewhere, so this becomes
plumbing."* It does not. There is no image, there never was one here, and the
work is exactly what step 2 always said: **install `qemu-system`, fetch the
official FreeBSD/amd64 qcow2, write the runner.**

Which is precisely what this session was told not to do, and rightly:
**plexus is the owner's workstation.** Installing a system emulator and
downloading a multi-gigabyte OS image is a change to their machine's
configuration, not a test-infra chore, and it is theirs to approve.

So step 1's real deliverable is the bounded request, filed as
[[decide-install-qemu-system-and-a-freebsd-image-on-plexus]] (Track U). This
ticket is **blocked on it** — genuinely blocked, on a one-line answer, not on
work.

### What is now known that was not

1. The lead "the image is on another box" is **closed**, with the evidence.
2. `qemu-user` vs `qemu-system` is the real gap, and it is a package install,
   not a hunt.
3. Disk is a non-issue: `/data` has 2.0T free.
4. The only remaining unknown is **the owner's consent**, which is a question,
   not a task.

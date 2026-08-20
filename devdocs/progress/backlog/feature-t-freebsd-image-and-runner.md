---
track: T
prio: 55
type: feature
blocked-by: []
summary: "Nothing on plexus can boot a FreeBSD kernel — qemu-system-x86_64 and qemu-img are not installed, /var/lib/libvirt/images does not exist, and no *freebsd* image is anywhere on the filesystem. That is the only thing standing between feature-port-freebsd-native and a start, and it is infrastructure, not compiler work, so it belongs to T."
status: backlog
owner: unassigned
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

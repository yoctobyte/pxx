---
slug: bug-s-install-esp32-target-names-a-package-that-is-virtual-only-on-26-04
track: S
type: bug
prio: 25
status: done
found: 2026-09-06
found-by: seven (Upgrade to 26.04 verification), filed by frank-coordinator
owner: frankS
blocked-by: []
summary: "FIXED 2026-09-23. `install_esp32_target.sh` asked for `qemu-user-static`, which is PURE VIRTUAL on 26.04 -- `apt-cache show`/`showpkg`/`dpkg-query` all succeed and only `apt-cache policy` says `Candidate: (none)` -- so the host-package loop warned and skipped it, and a fresh 26.04 box got no qemu binfmt registration at all. The script's `apt_has_candidate()` test was always right; only the NAME was stale. The fix generalises the entry to an ALTERNATIVES GROUP `qemu-user-binfmt|qemu-user-static` (first name with a candidate wins, missing only when NO member resolves), so one script stays correct across a rename instead of being pinned to whichever release its author was on. A t64 suffix and a cross-release rename are different transitions and the existing `<name>t64` fallback could not express the second."
---

# install_esp32_target.sh names a package that is virtual-only on 26.04

## The measurement (seven, on the box)

```
apt-cache show qemu-user-static      -> succeeds
apt-cache showpkg qemu-user-static   -> succeeds
dpkg-query                           -> succeeds
apt-cache policy qemu-user-static    -> Candidate: (none)      <- the only true answer
apt-get install qemu-user-static     -> E: has no installation candidate
```

Contrast rows, both measured:

| name | `Candidate:` |
| --- | --- |
| `qemu-user-binfmt` (real, present) | `1:10.2.1+ds-1ubuntu3.2` |
| `qemu-user-static` (virtual only) | `(none)` |
| a name that does not exist at all | empty |

**Three instruments answer a different question than the one asked, and none of
them errors.** `show` and `showpkg` answer *"is this name known to apt"*;
`dpkg-query` answers about the local database. Only `policy` answers *"can this
be installed here"*.

**The correct test is `Candidate:` non-empty AND not `(none)`** — it is the only
one that separates all three cases, and it needs the `(none)` arm, because an
absent name and a virtual name differ by which flavour of nothing they print.

## Status

- `tools/install_qemu.sh` (`038c3acf1`) uses the correct test.
- `tools/install_host_deps.sh` (`708337653`) reuses it and is **negative-controlled
  against both cases** — `cowsay` (real, absent) and `qemu-user-static` (virtual)
  land in two different categories.
- `install_esp32_target.sh`'s `apt_has_candidate()` **already does the right
  test**, which is why this warns instead of dying. Only the NAME is stale.

## The fix

Point line 96 at `qemu-user-binfmt`, keeping `qemu-user`. Verify on a 26.04 box,
not on one that already has the old package installed — **a host that has it
passes whether or not the name is right**, which is this repo's own one-target
hazard in the build-host variable.

Deliberately left alone by the session that measured it: one owner per thing,
and `tools/install_qemu.sh` owns qemu.

---

## RESOLUTION — 2026-09-23, frankS, on plexus (Ubuntu 26.04.1 LTS)

The ticket's measurement reproduces unchanged at HEAD on this box:

| name | `Candidate:` |
| --- | --- |
| `qemu-user-static` | `(none)` |
| `qemu-user-binfmt` | `1:10.2.1+ds-1ubuntu3.2` |
| `qemu-user` | `1:10.2.1+ds-1ubuntu3.2` |

**What landed is not the rename the ticket proposed.** A bare swap to
`qemu-user-binfmt` fixes 26.04 and is a guess about every other release --
it would move the failure to whichever release ships only the old name,
and the next person to hit it would swap it back. The host-package loop
now accepts an `a|b` ALTERNATIVES GROUP: the first member with a candidate
wins, and the group is reported missing only when NO member resolves. The
live entry is `qemu-user-binfmt|qemu-user-static`, newest first.

This is a different transition from the `<name>t64` fallback already in
that loop, which is why the fallback could not carry it: t64 is a
mechanical suffix on one name, a rename is two unrelated names.

### The controls, and why row 2 is the one that counts

Run against the file's own `install_host_packages` text (extracted by
function name, not retyped), with `sudo`/`apt-get` shimmed:

| # | group | expected | got |
| --- | --- | --- | --- |
| 1 | `qemu-user-binfmt\|qemu-user-static` | `qemu-user-binfmt` | pass |
| 2 | `qemu-user-static\|qemu-user-binfmt` | `qemu-user-binfmt` | pass |
| 3 | `nosuchpkg-aaa\|nosuchpkg-bbb` | missing, pkgs empty | pass |
| 4 | `qemu-user-static` alone | missing | pass |
| 5 | `libglib2.0-0` | `libglib2.0-0t64` | pass |
| 6 | `git wget binfmt-support` | all three kept | pass |

**Row 1 cannot distinguish a correct implementation from a first-wins-by-
position one** -- both predict `qemu-user-binfmt`, because the right answer
is also the first element. Row 2 reverses the order and is the only row
that shows the `Candidate:` test is what decides. Row 4 is the positive
control: it reproduces the original defect, so the harness is able to see
the bug at all. Row 5 proves the t64 path survived the rewrite.

A/B on the same harness, HEAD's file text versus the new one:

- **before:** `warn: no candidate for: qemu-user-static (skipped)`, and the
  install line carries `qemu-user binfmt-support` with no binfmt package.
- **after:** no warn at all, install line carries `qemu-user
  qemu-user-binfmt binfmt-support`.

### What I did NOT verify, and it is the ticket's own caution

The ticket warns that a host which already has the package passes whether
or not the name is right. Plexus does not have `qemu-user-static`
installed (it cannot be), so the 26.04 arm is measured. **The 24.04 arm is
NOT measured** -- I have no 24.04 box here. What the alternatives group
buys is that the 24.04 arm no longer depends on my being right about which
name that release ships: if `qemu-user-binfmt` is absent there, the group
falls through to `qemu-user-static`, and only a release shipping NEITHER
produces a warn. That is the property worth having, and it is the reason
the group beat the rename.

### Side finding, measured and NOT a defect

`[ -n "$missing" ] && say ...` at the end of that loop looks like a
`set -eu` footgun -- on a healthy host `$missing` is empty, the AND-OR
list returns 1, and the script would appear to exit before
`apt-get install` ever runs. **It does not.** Measured under both `sh` and
`dash`: a failing first command in a trailing AND-OR list is exempt from
`set -e`, the line is reached, rc=0. Recorded so the next reader does not
"fix" a working line -- the comment-versus-code guard, where the code was
right.

## Log
- 2026-09-23 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

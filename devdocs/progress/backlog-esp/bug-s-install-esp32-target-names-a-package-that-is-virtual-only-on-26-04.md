---
slug: bug-s-install-esp32-target-names-a-package-that-is-virtual-only-on-26-04
track: S
type: bug
prio: 25
status: backlog
found: 2026-09-06
found-by: seven (Upgrade to 26.04 verification), filed by frank-coordinator
owner: ""
blocked-by: []
summary: "`tools/install_esp32_target.sh:96` asks for `qemu-user-static`, which on 26.04/resolute survives as a PURE VIRTUAL package: three instruments say it exists and only `apt-cache policy` says it cannot be installed. The script's own `apt_has_candidate()` already does the correct `Candidate:` test, so it WARNS rather than dying and blocks nobody today -- but it will not install the renamed package on a fresh 26.04 box. Not urgent; filed so the rename lands with the measurement rather than being rediscovered. The real package is `qemu-user-binfmt`."
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

---
track: D
prio: 10
type: bug
blocked-by: []
status: done
found-by: frankd-23 (the v450 archive); routed by frankuser as beta-critical; fixed by frankD
tags: [cli, release, bug-reports, version]
summary: "`pxx --version` and `--doctor` printed no build identity, and the release notes' bug-report step asked for `git log`, which someone using an archive cannot run. Both now print `build: sha256 <first 12>`, the binary's own SHA-256 computed at run time. Under it they print what a record next to the binary says about that hash: `release`/`source`/`pin` from MANIFEST.sha256 plus the new RELEASE-ID in a bundle, `pin`/`source` from pin.log in a checkout, `local` for a `make` build, and `local: not a pin or a release binary` otherwise."
owner: ""
---

# `pxx --version` prints no build identity

## Why run time, not build time

A binary cannot contain its own hash. A source commit embedded at build time
would make the binary's bytes depend on git state, so `selfcheck.sh`, which
rebuilds a bundle's binaries from the tarball where there is no `.git`, would
stop reproducing MANIFEST.sha256. So the compiler hashes `/proc/self/exe`
(SHA-256, in compiler.pas) and looks for that hash in records that already
name binaries by hash:

| Where | Record | Prints |
| --- | --- | --- |
| release bundle | `MANIFEST.sha256`, then `RELEASE-ID` | `release:` tag "codename", `source:`, and `pin:` when the release binary is the pin |
| checkout | `stable_linux_amd64/default/pin.log` | `pin:` vNNN, `source:` the commit the pin was cut from |
| checkout | `compiler/.pascal26.fixedpoint` | `local:` the last `make`, and its source hash |
| anywhere else | none | `local: not a pin or a release binary` |

A line is printed only when a record names the hash. A VERSION file that
happens to sit nearby does not count.

`tools/release.sh`'s `build_dist` now writes `RELEASE-ID` (tag, codename,
source commit, and pin only when the release binary is the pinned one). The
bundle's RELEASE.md lists it.

## Measured (2026-09-29, fixedpoint d67ea56f34a7)

- The `build:` value equals `sha256sum`'s first 12 digits for the binary with
  0 to 63 extra bytes appended, which covers every padding case of the last
  block (64 of 64).
- A bundle made by the real `build_dist` (x86_64 only), then extracted fresh:
  `compiler/pxx-x86_64 --version` and `compiler/pascal26 --version` both print
  `release: v0.1.0-beta.2 "Blaise"` and `source: ab6ab895b9bc`. There is no
  `pin:` line, correctly, since that binary is not the pin.
- Checkout: a `pin.log` line in the real format that names the binary gives
  `pin: v452` and `source:`, whether the binary sits in
  `stable_linux_amd64/default/` or in `compiler/`. The `make` build gives
  `local:` with the stamp's source hash. A copy with no record gives
  `local: not a pin or a release binary`.
- `--version` takes about 0.5 s on this 8.8 MB binary, because of the hash.
- A Makefile row checks the `build:` line of both flags against `sha256sum`.
  The v451 pinned binary fails it.
- docs: reporting-bugs.md, release-notes/index.md and cli.md now ask for
  `--version`. They keep the `sha256sum` line for the v0.1.0-beta.1 archive,
  whose binary predates this change.

# Release packaging, reproducibility manifest, and `release.sh`

- **Type:** feature (project infrastructure / distribution)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21 (release-model design discussion)
- **Relation:** builds on `make stabilize`/`make pin` (the existing blessed-binary
  mechanism) and `make cross-bootstrap` (all-target byte-identical proof). The
  daily `stable_linux_amd64` pin is internal dev ground; this ticket is the
  user-facing, tag-bound release on top.

## Model — a toolchain release, not an app release

PXX is a compiler (toolchain), so it ships like gcc/FPC/rustup, **not** like a
desktop app. AppImage/snap/flatpak solve GUI runtime dependency-hell and add
sandboxing that fights a tool whose job is reading/writing arbitrary files —
explicitly **not** used here. The PXX compiler binary is freestanding-ish (own
RTL, raw syscalls), so it needs no bundling.

### What a release contains
1. **Source** (the tag tarball — GitHub auto-generates it). The RTL/PCL **must**
   ship as source: PXX compiles `lib/rtl` + `lib/pcl` from source on every build
   ("own RTL from scratch"; no precompiled `.a`). So source isn't bloat — it's the
   floor, and tinkerers get it for free.
2. **Host binaries** for the 4 Linux host arches: x86_64, i386, aarch64, arm32
   (all produced byte-identical by `make cross-bootstrap`). xtensa/riscv32 are
   **emit-only targets**, not hosts — no "xtensa compiler binary".
3. **`setup.sh`**: detect `uname -m`, symlink the native binary to `pxx` on PATH.
   Nothing else — the compiler already resolves `lib/rtl`, `lib/pcl`, `builtin/`
   relative to its own binary via `ExeDir` (`<root>/compiler/ -> ../lib/...`,
   parser.inc ~10752; compiler.pas ~336/349). **Preserving the tree layout makes
   an unpacked release work from anywhere** — this is the linchpin; keep it solid.

### Install layout (FPC-shaped, devs recognize it)
```
pxx-vNN/
  bin/  pxx-x86_64  pxx-aarch64  pxx-i386  pxx-arm32
  lib/  rtl  pcl                 # source, ExeDir-resolved
  builtin/                       # frozen builtin RTL
  examples/   README   setup.sh   MANIFEST.sha256
```

## Reproducibility — the ultimate post-install / bringup check

Codegen output is a pure function of **(source, target)**, **independent of host**
(proven by the cross-bootstrap triple-stage: native emits `--target=T`, that
binary under QEMU emits `--target=T`, byte-identical). Consequences:

- The release carries a **per-target SHA256 manifest** (one hash per target, host-
  independent), committed/attached **at the tag** so `{source, manifest}` is frozen
  atomically.
- **Any single host reproduces the entire release**: run the native `pxx` with each
  `--target=`, compile `compiler/compiler.pas`, hash, compare to the manifest. An
  arm32 box reproduces the x86_64 release binary bit-for-bit. So a user verifies
  the *whole* release from one machine — independent reproduction = supply-chain
  trust (don't trust the binary, reproduce it).

### `pxx --selfcheck` / `make verify-install` — two distinct checks
1. **Self-fixedpoint, native** (`pxx -> gen1 -> gen2`, `cmp gen1 gen2`): determinism
   on *this* silicon/kernel. Needs **no manifest**, always runs (HEAD or tag). This
   is the hardware/kernel/CPU probe (catches non-determinism, missing instructions,
   the suspected-bit-flip canary). Also the **new-hardware bringup test** (point it
   at a new arch/kernel/QEMU and it tells you instantly if codegen + ABI are sound).
2. **Reproduce-all-targets vs manifest**: validates the full release reproducibility.
   Only meaningful when source == the tagged source. Compare embedded version /
   `git describe` to the manifest tag: match -> run (hard); mismatch (HEAD ahead) ->
   print "no release manifest for this source; determinism-only" and **skip, don't
   fail**. (xtensa/riscv32: reproduction verified by emit-hash; *execution* only via
   QEMU/hardware, since they don't self-host.)

Asymmetry is correct: **determinism = property of (host, source)** — always testable;
**reproducibility = property of (source == tagged source)** — tag-only.

## nightly != release
- **nightly / per-push**: source + the CI gate (`make test` = self-host fixedpoint +
  determinism). **Publishes no binaries.** A green checkmark means "releasable".
- **release**: a **git tag** only. Binaries + manifest are built **at tag time**, never
  per-commit (rebuilding all targets every push is wasted work).
- Keep **`stable_linux_amd64` pin** (internal, x86_64-only, frequent, Track B's
  ground) **distinct** from the **release manifest** (all-target hashes, rare,
  user-facing, tag-bound). Different cadence, different audience — don't conflate.

## Versioning — semver tags, not a custom string

Tags are `vMAJOR.MINOR.PATCH` with the prerelease channel in the suffix:
`v0.1.0-alpha.1` -> `-beta.1` -> `-rc.1` -> `v0.1.0`, GitHub `--prerelease` until
the bare `v0.1.0`. **`0.x` already means "unstable, expect breakage"** — don't
double-encode with `preview`/`beta` words (and `0.01` doesn't parse/sort). Semver
sorts correctly and is parseable by the tag tooling / `git describe` selfcheck —
a custom string like `preview-beta-0.01` is not. Pre-1.0 semantics (loose):
MAJOR = language/emitted-ABI break, MINOR = features/new targets, PATCH = bugfix.
Keep the internal **pin counter** (`stable_linux_amd64` `VERSION`, currently v32)
**separate** from the public semver — pin = dev checkpoint, tag = release.

The channels (`alpha`/`beta`/`rc`) are just **ordered labels** on a monotonically
increasing version; semver already orders them (`alpha < beta < rc < stable`), so
they sort and the publish tool can enforce "strictly greater than last". A
**per-release codename** (decorative) rides in the GitHub Release title/notes, not
in the tag (tag stays pure semver). `tools/release.sh` drives the bump + codename
interactively — see its section below.

## GitHub mechanics — branch push = CI, tag = release

One x86_64 runner cross-builds **all** targets (host-independent codegen → no arch
matrix needed; QEMU only if CI should also run each arch's self-fixedpoint).

- **`.github/workflows/ci.yml`** — `on: [push, pull_request]`: `make test`
  (+ optional `make cross-bootstrap`). Publishes nothing.
- **`.github/workflows/release.yml`** — `on: push: tags: ['v*']`:
  `make release` then `gh release create "$GITHUB_REF_NAME" dist/*` (gh + GITHUB_TOKEN
  are preinstalled/auto on runners; `permissions: contents: write`). Publishes only
  if `make release` succeeds, so **a release can't ship unless reproduction holds.**

Cutting a release = `git tag v0.1.0 && git push origin v0.1.0` (fires release.yml).
The tag freezes `{source, manifest}` — the invariant enforced by Git.

## Deliverables

- **`make release`** — cross-bootstrap every target, assert all reproduced
  byte-identical, `sha256sum` each -> `MANIFEST.sha256`, assemble `dist/pxx-<tag>/`
  + tarball. The only thing that builds binaries.
- **`make verify-install`** / **`pxx --selfcheck`** — the two checks above.
- **`tools/release.sh`** — user-facing wrapper (see below).
- **`setup.sh`** — arch-detect + PATH symlink (in-place install; ExeDir handles libs).
- The two GitHub workflow YAMLs.

## `tools/release.sh` — dry-run by default, explicit `--publish`

Avoid littering git/GitHub with test releases: **default is a no-side-effect
rehearsal.**

- **Default (no `--publish`)**: run `make release` locally → build all targets,
  verify byte-identical reproduction, generate the manifest, assemble `dist/`, run
  `--selfcheck`. **Report what *would* be tagged/published. Create/push NO tag,
  cut NO GitHub Release.** Idempotent, repeatable, safe.
- **`--publish`**: only after the rehearsal passes — create the annotated tag and
  `git push origin <tag>` (fires `release.yml`). (Or `--local`: `gh release create`
  with locally-built `dist/` assets — but tag-driven CI is preferred: clean-room.)

### Interactive version + codename (idiot-proof — the maintainer never hand-types a tag)

`release.sh` is the *maintainer's* publish tool; idiot-proof *its own* process
(no malformed tags, no version regression, no skipped channel). **Never accept a
free-typed version** — compute and confirm from a menu.

- **Read the last tag** (`git describe --tags --abbrev=0`), then present the next
  steps as a menu, auto-computing each candidate so the user just picks:
  - bump **patch** (`0.1.0 -> 0.1.1`)
  - bump **minor** (`0.1.0 -> 0.2.0`)
  - bump **major** (`0.1.0 -> 1.0.0`)
  - bump the **prerelease counter** within the channel (`...-beta.1 -> ...-beta.2`)
  - **advance the channel** (`alpha -> beta -> rc -> stable`) — ordered, one step
  - **promote to stable** (drop the suffix: `0.2.0-rc.3 -> 0.2.0`)
  Each printed with the literal resulting tag. The channels are just ordered
  labels; semver's prerelease ordering (`alpha < beta < rc < <stable>`) is the
  underlying monotonic spine, so the tool can *enforce* "strictly greater than the
  last tag" and refuse any regression or out-of-order channel jump.
- **Codename**: prompt for one (decorative, per-release). Optionally **auto-suggest**
  the next from a themed wordlist (e.g. alphabetical sequence) so naming stays
  consistent without thought; user accepts or overrides. Recorded in a codename
  ledger (`docs/release-notes/` or a `CODENAMES` file) and used in the GitHub
  Release **title/notes**, not the version tag (the tag stays pure semver so tooling
  parses it).
- **Confirm-before-act**: show the final `{tag, codename, channel, what fires}`,
  require an explicit `yes`. Dry-run still the default; `--publish` + the confirmation
  are the only side-effecting path.
- **Guard rails (refuse to publish if):** working tree dirty; not synced with origin;
  `make test` / `make release` not green; computed tag already exists; computed tag
  not strictly greater than the last (regression); channel jump skips a step. Print
  each failed guard explicitly with the fix.

## Non-goals
- AppImage / snap / flatpak (wrong tool class).
- macOS / Windows hosts (compiler emits Linux ELF; no host port yet).
- Signing (cosign/minisign) — high-value follow-up to strengthen "reproduce +
  verify signature", but not required for v1.
- Per-arch native CI runners (cross-determinism makes them unnecessary).

## Now vs later (not building a release yet)
- **Now (cheap anticipation):** keep `ExeDir`-relative lib resolution robust — add a
  test that the binary works run from outside the repo with only the tree present.
  Optionally stub `make release` as the existing cross-bootstrap loop + `sha256sum`.
- **Later (first real release):** write `make release` + `tools/release.sh` + the two
  YAMLs + `setup.sh`; then optionally signing and a scheduled nightly prerelease.

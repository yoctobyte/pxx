---
prio: 35
track: D
---

# Document the toolchain information flags (--help / --version / --where / --config / --list-targets / --list-libraries / --doctor, PXX_HOME, PXX_LIBPATH, pxx.cfg)

- **Type:** docs
- **Status:** backlog
- **Track:** D (docs) — filed by Track A, which landed the flags but does not own `docs/**`
- **Opened:** 2026-08-21
- **Relation:** `feature-toolchain-cli-ux` (Track A) landed the flags; this ticket
  is only the user-facing prose.

## What landed and now needs documenting

`pxx` answers these with **no source file**, exit 0 (verified by rows in
`test-quick`):

- `--help` / `-h` — usage + the options worth remembering.
- `--version` — generation (`PXX_GENERATION`, the same number `{$IF PXX_VERSION
  >= n}` tests), frontend list, host.
- `--list-targets` — the `--target=` values, which run on this host, which
  backends are compiled out, and the ESP SoC names.
- `--where` — every resolved path with the tier it came from, `[MISSING]` marked.
- `--config` — an ALIAS for `--where` (byte-identical output, asserted in
  test-quick), for when the question is "which pxx.cfg is in effect?".
- `--list-libraries` — the units this binary can actually find, grouped by
  directory, plus a curated "external integrations" section (ESP-IDF, Synapse)
  with prerequisites. Scanned, never recited: it lists what you can `uses`, and
  deliberately says nothing about what each unit DOES — that part is this
  ticket's job, in docs/, where it can be written once and reviewed.
- `--doctor` — capability report: native compile, RTL/builtin/headers found,
  cross-run per target (qemu), ESP-IDF + Espressif toolchain, FPC seed, gdb,
  gcc. Every NO row says what to install. Nothing in it is fatal.

Plus the environment tier:

- `PXX_HOME=<root>` — install root; replaces the roots guessed from the binary's
  own directory (`lib/rtl`, `lib/pcl`, `lib/asmcore`, `compiler/builtin`,
  `lib/crtl/include`, and the PAL dir). Honoured **all-or-nothing**: the exe-dir
  guesses are NOT kept underneath it as a fallback.
- `PXX_LIBPATH=a:b` — extra Pascal unit roots; after `-Fu`, before the defaults.
- `PXX_CONFIG=<file>` and the `pxx.cfg` search order (`$PXX_CONFIG`, `./pxx.cfg`,
  `~/.config/pxx/pxx.cfg`, `<exe dir>/pxx.cfg`, first wins) with the three
  directives that exist today: `home`, `unitpath`, `incpath`.

## Where it belongs

Getting-started / install: "units not found" is the single most common first
failure, and `pxx --where` is the one-command answer — worth naming there rather
than burying in an option table. `PXX_HOME` is what makes an unpacked tarball
work from any directory.

## Do not

- Re-derive the search order in prose. `--where` prints it from the code that
  performs it; docs should say "run `pxx --where`", not restate a rule that will
  drift. A short worked example of its OUTPUT is fine and useful.
- Document `--config`, `--list-libraries`, `--doctor`, `--selfcheck` or a
  `pxx.cfg` file — none of those exist yet; they are open steps 3-4 of
  `feature-toolchain-cli-ux`.

---
prio: 45  # auto
---

# Toolchain CLI / user tooling (install, config, discovery, doctor, selfcheck)

- **Type:** feature (project infrastructure / user experience)
- **Status:** backlog (steps 1-2 landed 2026-08-21; 3-4 open)
- **Owner:** agent-A
- **Opened:** 2026-06-21 (user-tooling design discussion)
- **Relation:** companion to `feature-release-packaging` — that ticket *produces &
  distributes* the artifacts; this one is the *user experience once installed*.
  `setup.sh` and `pxx --selfcheck` are defined there and referenced here (no
  duplication: release-packaging owns produce/distribute, this owns the CLI/UX).

## Shape: installer is a script; everything else is a `pxx` flag

- The **installer (`setup.sh`)** must be a separate script — it runs *before* `pxx`
  is on PATH (arch-detect + symlink). Owned by `feature-release-packaging`.
- Everything else is a **flag/subcommand on the `pxx` binary** — always present
  post-install, no extra files, self-documenting via `pxx --help`. This matches
  the toolchain idiom (gcc/fpc/rustc subflags) and avoids a litter of helper
  scripts that "confuse users".

## Config resolution (the foundation — get this right first)

The compiler already anchors `lib/rtl`, `lib/pcl`, `builtin/` to `ExeDir`
(`<root>/compiler/ -> ../lib/...`). Generalize to an explicit, inspectable order:

1. CLI flags (`-Fu`, `-I`) — highest.
2. Env (`PXX_HOME`, optional `PXX_LIBPATH`) — for non-default installs.
3. A config file (`pxx.cfg`, FPC-`fpc.cfg`-analog) next to the binary or in
   `~/.config/pxx/` — optional.
4. `ExeDir`-relative defaults — the zero-config install path (works today).

Lower tiers are fallbacks; nothing required for a normal unpack-and-run install.

## `pxx` flags to add

- **`pxx --version`** — semver + the build/pin it came from + target list summary.
- **`pxx --where`** / **`pxx --config`** — print resolved paths (ExeDir, rtl, pcl,
  builtin, config file in effect) and *which tier* each came from. The first thing
  to reach for when "units not found".
- **`pxx --list-targets`** — the supported `--target=` values
  (x86_64/i386/aarch64/arm32/xtensa/riscv32) + which are host-capable vs emit-only.
- **`pxx --list-libraries`** — discoverability for the stdlib + the *external
  integration* libraries and their status/prerequisites:
  - bundled RTL/PCL units (always available).
  - **IDF** (ESP-IDF app path): needs `--target=xtensa|riscv32 --emit-obj` + the
    Espressif toolchain/IDF env; point at `examples/esp32/*`.
  - **Synapse** (networking via the Delphi-Posix path): its define profile + the
    posix syscall shim units; status = in-progress.
  - Each entry: name, one-line purpose, availability/prereqs, a pointer to an
    example or ticket. Honest about "in-progress/experimental".
- **`pxx --selfcheck`** — defined in `feature-release-packaging`: native
  self-fixedpoint (determinism, always) + reproduce-all-targets vs manifest
  (tag-only, graceful-degrade). The post-install / bringup test.
- **`pxx --doctor`** — environment capability report: what each capability needs
  and whether it's present. E.g. *rebuild-the-compiler* needs an FPC seed;
  *cross-run/selfcheck of non-native arches* needs QEMU; *ESP targets* need the
  Espressif toolchain; *GTK/PCL demos at runtime* need libgtk. Print per-capability
  OK/missing + how to get each. Turns "why doesn't X work" into one command.

## Native-target detect + alias

`uname -m` -> the matching `bin/pxx-<arch>` -> symlink/alias `pxx`. Lives in
`setup.sh` (pre-PATH); `pxx --where` confirms which binary is active afterward.
(Overlaps `feature-release-packaging` `setup.sh` — implement once there, surface
the result here via `--where`.)

## Non-goals
- A package-manager / dependency-fetcher for third-party PXX libraries (later, if
  an ecosystem appears).
- GUI/TUI config — flags + a plain config file only.
- Duplicating the produce/distribute logic — that's `feature-release-packaging`.

## Sequencing
1. **Config resolution** (tiers above) + `pxx --where` — foundation, makes every
   "can't find units" issue self-diagnosable. Highest value, do first.
2. `pxx --list-targets` / `--version` — trivial, ride on existing data.
3. `pxx --list-libraries` + `pxx --doctor` — discoverability/diagnostics; grow the
   library registry as IDF/Synapse/etc. mature.
4. `pxx --selfcheck` — with `feature-release-packaging` (needs the manifest).

## Landed 2026-08-21 — steps 1 (partly) and 2

Everything below is a flag on the binary, answering with **no source file** and
exiting 0, and covered by rows in `test-quick` (so `gate.sh quick` sees them).

- `--version` — generation, frontend list, host. The generation number now has
  ONE owner: `PXX_GENERATION` in `defs.inc`, which `lexer.inc` also feeds to the
  `PXX_VERSION` define, so `{$IF PXX_VERSION >= n}` and `--version` cannot
  disagree.
- `--list-targets` — every `--target=` value, which run on this host, and which
  backends are compiled OUT (`-dPXX_NO_I386` / `-dPXX_NO_ARM32`); plus the ESP
  SoC names.
- `--help` / `-h` — usage, the information flags, the options worth remembering,
  and the environment section below.
- `--where` — every resolved path, tier by tier, each marked `[MISSING]` when it
  does not exist. It calls the SAME routines a real compile calls
  (`ResolveToolchainDirs`, `AddDefaultPasUnitDirs`, `AddDefaultCIncludeDirs`),
  which is the whole point: the ticket asks for a diagnostic, and a diagnostic
  that re-derives the search rule is one that goes stale silently and then sends
  the reader hunting in the wrong place. Making that true required extracting
  two blocks that had been inline (`ParseUsesUnit`'s library-dir resolution, the
  main body's PAL-dir defaults) into named procedures — the diagnostic is now
  physically unable to disagree with the search.
- **Tier 2 of the config order: env.** `PXX_HOME=<root>` replaces the
  ExeDir-guessed roots (`lib/rtl`, `lib/pcl`, `lib/asmcore`, `compiler/builtin`,
  `lib/crtl/include`, the PAL dir); `PXX_LIBPATH=a:b` adds unit roots after
  `-Fu` and before the defaults. `PXX_HOME` is honoured **all-or-nothing** — the
  exe-dir guesses are not appended underneath it as a silent second chance,
  because a half-applied override is the failure mode nobody can read, and
  `--where` prints a typo as `[MISSING]`.
- One env reader: `PxxGetEnv` in `defs.inc` reads `/proc/self/environ` once
  through the sysopen/sysread intrinsics (so it serves the FPC-bootstrap and
  self-hosted builds alike); `PXXDBG` now reads through it instead of
  hand-rolling the same scan.

Checked, not assumed: a binary copied outside the tree compiles `uses sysutils`
under `PXX_HOME` and fails without it; the stable-layout probe re-anchor is
visible in `--where` from a fake two-levels-down install; and the same source
compiled with and without `PXX_HOME` emits **identical bytes** — the env tier is
a second door onto `bug-a-the-compilers-output-depends-on-argv0`, and it is shut.

### Still open (why this returns to backlog, not done)
- ~~Tier 3, the config file~~ — landed the same night under
  `feature-dynamic-include-paths-config`: `pxx.cfg` with `home` / `unitpath` /
  `incpath`, found via `$PXX_CONFIG`, `./pxx.cfg`, `~/.config/pxx/pxx.cfg`,
  `<exe dir>/pxx.cfg` (first wins), and reported by `--where`. Scoped
  `define`/`mode` manifests stay with that ticket.
- `--config` as a separate spelling — `--where` currently answers both.
- Step 3: `--list-libraries`, `--doctor`.
- Step 4: `--selfcheck` (needs `feature-release-packaging`'s manifest).
- User-facing docs for the four flags are a **Track D** job, not filed here.

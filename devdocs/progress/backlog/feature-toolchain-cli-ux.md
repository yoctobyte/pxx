---
prio: 45  # auto
---

# Toolchain CLI / user tooling (install, config, discovery, doctor, selfcheck)

- **Type:** feature (project infrastructure / user experience)
- **Status:** backlog
- **Owner:** —
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

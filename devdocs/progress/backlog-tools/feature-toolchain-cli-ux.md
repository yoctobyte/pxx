---
slug: feature-toolchain-cli-ux
title: "Toolchain CLI / user tooling (install, config, discovery, doctor, selfcheck)"
track: T
prio: 30
type: feature
status: backlog
owner: ""
blocked-by: [decide-what-should-pxx-selfcheck-assert-when-the-compiler-cannot-spawn]
summary: "FIVE OF THE SIX FLAGS ARE LANDED AND THE SIXTH IS A DECISION, NOT AN IMPLEMENTATION. `--version`, `--where`/`--config`, `--list-targets`, `--list-libraries` and `--doctor` all answer with no source file and exit 0, are covered by test-quick rows so gate.sh quick sees them, and are built to be unable to drift: `--where` calls the SAME routines a real compile calls (ResolveToolchainDirs / AddDefaultPasUnitDirs / AddDefaultCIncludeDirs) rather than re-deriving the search rule, and `--list-libraries` SCANS the resolved directories through PxxListDir rather than reciting an inventory. Config tiers 1, 2 and 3 are all in: CLI flags, then PXX_HOME/PXX_LIBPATH (all-or-nothing, so a typo shows as [MISSING] instead of half-applying), then pxx.cfg, then ExeDir defaults. ONLY `--selfcheck` IS LEFT, it answers `unknown option` (re-measured 2026-09-05 at HEAD), AND IT IS BLOCKED ON INTENT rather than on work: feature-release-packaging specifies check 1 as `pxx -> gen1`, `gen1 -> gen2`, `cmp gen1 gen2` -- a real fixedpoint STEP that requires RUNNING the freshly built binary -- while the compiler spawns no process (no PalVforkAndExec/PalFork anywhere under compiler/) and locates itself only through ExeDir. Every in-process substitute asserts something WEAKER under the same trusted name, and tools/selfcheck.sh already does the specified thing and already ships in the release tree, so `do nothing` is a live option. Filed as [[decide-what-should-pxx-selfcheck-assert-when-the-compiler-cannot-spawn]] with four options and a recommendation; that ticket is still `status: new`, `owner: user`. IF THE ANSWER IS `USE THE SCRIPT`, THIS TICKET CLOSES ON THE ANSWER ALONE. User-facing docs for the five landed flags are a Track D job and are not filed here."
---

# Toolchain CLI / user tooling (install, config, discovery, doctor, selfcheck)

- **Type:** feature (project infrastructure / user experience)
- **Status:** backlog, blocked on a Track U decision (steps 1-3 landed
  2026-08-21; step 4 `--selfcheck` no longer waits on `feature-release-packaging`,
  which is `done` — it waits on
  [[decide-what-should-pxx-selfcheck-assert-when-the-compiler-cannot-spawn]])
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

## Landed 2026-08-21 — step 3: `--list-libraries` and `--doctor`

Both answer with no source file and exit 0, like the other four.

**`--list-libraries` SCANS, it does not recite.** The unit lists come from a new
`PxxListDir` over exactly the directories `ResolveToolchainDirs` resolves, so a
unit appears the day it lands and a hardcoded inventory cannot go stale. The
cost, stated rather than hidden: it says what you can `uses`, not what each unit
DOES — a one-line purpose per unit kept in `compiler.pas` would drift for
precisely the reason the scan exists. External integrations (ESP-IDF, Synapse)
are a separate, curated section, because they are not units in this tree and
their answer is a toolchain prerequisite rather than a filename.

A directory that does not resolve is REPORTED as `[MISSING]`, never omitted: an
empty section reads as "this library does not exist", which is the wrong
diagnosis for what is nearly always a path problem.

**`--doctor` reports CAPABILITY, not inventory.** Every row is something you
might try to do — run an aarch64 binary, flash an ESP32, cold-bootstrap from
FPC, step in gdb — and a NO row says what to install, because `qemu-aarch64:
not found` three commands later is the same information delivered at the worst
moment. Nothing in it is fatal and the last line says so: pxx compiles and runs
native programs with every row missing.

Probing without `execve` (the self-hosted compiler has none): `WhichOnPath`
walks `$PATH` and `sysopen`s each candidate — a tool nobody may read is not one
this compiler could hand work to either.

### One directory scanner, not two

`--list-libraries` needed a directory listing, and one already existed inside
`ResolveCaseInsensitivePath` (elfwriter.inc) as an inline `getdents64` walk with
an FPC `FindFirst` twin. Copying it would have been the smaller diff and the
wrong move — `devdocs/dev/normalise-dont-special-case.md` is about exactly this,
and the copy nobody runs is the one that rots (this session already found five
such files in the sweep). So the walk became `PxxListDir`, and
`ResolveCaseInsensitivePath` is now a `CaseEqual` loop over its result.

Safe to share because the fallback is not a hot path: it runs only after
`LoadFile` returned empty. Verified both directions afterwards — `uses myunit`
resolving `MyUNIT.pas` through the fallback, and the exact-case file still
resolving without it.

`DirEntTruncated` is not decoration. A scan that silently stopped at the cap
would make a MISSING unit look like a case mismatch, so the fallback refuses to
answer when it is set.

### Still open (why this returns to backlog, not done)
- ~~Tier 3, the config file~~ — landed the same night under
  `feature-dynamic-include-paths-config`: `pxx.cfg` with `home` / `unitpath` /
  `incpath`, found via `$PXX_CONFIG`, `./pxx.cfg`, `~/.config/pxx/pxx.cfg`,
  `<exe dir>/pxx.cfg` (first wins), and reported by `--where`. Scoped
  `define`/`mode` manifests stay with that ticket.
- ~~`--config` as a separate spelling~~ — landed 2026-08-21 as an ALIAS, not a
  second report: `--config` and `--where` print the same page, asserted
  byte-identical in test-quick. Two reports where one answers both questions is
  how the pair drifts, and the drifted one is always the one you are reading.
- ~~Step 3: `--list-libraries`, `--doctor`~~ — landed 2026-08-21 (above).
- Step 4: `--selfcheck` (needs `feature-release-packaging`'s manifest).
- User-facing docs for the four flags are a **Track D** job, not filed here.


---

## 2026-09-02 (frankH) — step 4 is unblocked, and it is a fork rather than an implementation

`feature-release-packaging` is in `done/`, so the stated wait is over. Measured
on `8616ed370fa7`: `--version`, `--where`, `--list-targets`, `--list-libraries`
and `--doctor` all answer with no source file and exit 0. `--selfcheck` is
`unknown option`. It is the only item left.

It is not a small implementation. The spec in `feature-release-packaging`
defines check 1 as `pxx -> gen1`, then `gen1 -> gen2`, `cmp gen1 gen2` — a real
fixedpoint STEP, which means running the freshly built binary. **The compiler
spawns no process** (no `PalVforkAndExec` / `PalFork` anywhere under
`compiler/`) and locates itself only through `ExeDir`. Every in-process
alternative asserts something weaker or noisier under the same trusted name, and
`tools/selfcheck.sh` already does the specified thing and already ships inside
the release tree.

Filed as
[[decide-what-should-pxx-selfcheck-assert-when-the-compiler-cannot-spawn]] with
four options and a recommendation. **If that decision is "use the script", this
ticket closes on the answer alone** — the other five flags are done.


## 2026-09-05 (frankH) — re-measured, and the frontmatter was the defect

Nothing has moved on the work: `--selfcheck` still answers `unknown option` at
HEAD, and the decision it waits on is still `status: new`, `owner: user`, filed
2026-09-02.

What HAD moved is that this ticket said so **only in prose**. Its frontmatter was
two lines — `prio` and `track` — with no `blocked-by`, no `status`, and **no
`summary` at all**, so `ready --track T` offered it as unblocked work and the
only part everyone reads did not exist. The next taker would have re-derived the
same fork: five flags done, one blocked on intent, discoverable in about twenty
minutes of reading.

Frontmatter modernised and the blocking edge recorded where the tooling can see
it, per the convention `progress.sh check` prints: prose stating a blocking
relationship must also carry the frontmatter edge.

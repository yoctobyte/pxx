---
prio: 35
track: D
owner: frankD
---

# Document the toolchain information flags (--help / --version / --where / --config / --list-targets / --list-libraries / --doctor, PXX_HOME, PXX_LIBPATH, pxx.cfg)

- **Type:** docs
- **Status:** done
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

## Log
- 2026-08-29 — resolved, commit 2d096462e.

---

## RESOLVED 2026-08-29 (frankD)

Landed across three pages: the reference gets the substance, install gets the
first-failure answer, getting-started gets a one-paragraph pointer from the place
the failure actually happens.

### The ticket's "Do not" list was stale, and the parent ticket proves it

It said `--config`, `--list-libraries`, `--doctor`, `--selfcheck` and `pxx.cfg` do
not exist and are open steps 3-4. Measured against pinned v391 instead of taken on
faith — all of them answer except `--selfcheck`, which really is absent
(`unknown option: --selfcheck`, exit 1). `feature-toolchain-cli-ux`'s own status line
reads *"steps 1-3 landed 2026-08-21; step 4 `--selfcheck` waits on
feature-release-packaging"* — i.e. step 3 landed the same day this ticket was filed,
and the "Do not" paragraph was written from the snapshot an hour earlier. Everything
but `--selfcheck` is therefore documented; `--selfcheck` is not mentioned at all.

### What went where

- **`docs/reference/cli.md`** — new `## Information flags` before `## Options`: the
  six-flag table, `--version`'s output, a `### --where` subsection, and a
  `### --doctor` one. New `## Environment and pxx.cfg` before `## Examples`:
  `PXX_HOME` / `PXX_LIBPATH` / `PXX_CONFIG`, the all-or-nothing rule with the error
  it produces, and the config search order with its three directives. `## Search
  paths` now points at `--where` instead of growing a second copy of the order.
- **`docs/install/index.md`** — `## Checking an install, and fixing "unit source not
  found"`, plus `### Running from an unpacked tarball: PXX_HOME`.
- **`docs/getting-started/index.md`** — one paragraph under the first program, where
  a reader meets `unit source not found` for the first time.

### The "do not re-derive the search order" instruction, honoured

No page restates the resolution rule. Each says *run `pxx --where`*, and the two
excerpts of its **output** are exactly the worked example the ticket allowed. The
tier order appears only as the footer `--where` itself prints.

### One overclaim caught and defused

`--version` prints `frontends: pascal c nilpy rust zig ada basic fortran algol
erlang lolcode whitespace` — a hand-maintained string at `compiler/compiler.pas:272`,
not a registry read. Reprinting twelve frontends unqualified would read as a support
claim for Ada and Fortran. They are real (each gave a frontend-specific diagnostic
when fed the wrong source, so the lexers and parsers genuinely run) but their own
tickets call them *"Esoteric probe"* — except BASIC, *"a real demo target, not an
esoteric probe"*. The page prints the line verbatim and adds one sentence: this is
every frontend compiled in, at very different stages; the ones these docs cover are
Pascal, C and Nil Python; the rest are experimental frontends and probes, and their
presence in the list is not a support claim.

`docs/**` mentions none of the seven — filed separately as
[[docs-d-the-version-flag-advertises-seven-frontends-the-docs-never-mention]]
rather than smuggled into this ticket.

### Measured — pinned v391, no rebuild

- all eight flags run and their exit codes checked; `--config` diffed against
  `--where`: **byte-identical**, as the ticket claimed;
- `PXX_HOME=/opt/pxxfake` — every root re-rooted under it and marked `[MISSING]`,
  and a real compile then fails `uses: unit source not found: platform_backend`.
  All-or-nothing confirmed by behaviour, not by reading the footer;
- `-Fu` **outranks** it: the same broken `PXX_HOME` plus explicit `-Fu` roots
  compiles and runs. That is why the install page tells the reader to use a wrapper
  or `PXX_HOME`, not both — a wrapper passes `-Fu`, so it silently wins;
- `PXX_LIBPATH=/opt/a:/opt/b` with `-Fu/opt/flag` lands in the order the docs state:
  flag, then the two env roots, then the defaults;
- `PXX_CONFIG` pointed at a scratch `pxx.cfg` — `--where` echoes the chosen file and
  the directives read from it;
- the quoted `[MISSING]` line, the tier-order footer and the error text are copied
  from real output, not paraphrased.

### Left alone

The `./pxx` wrapper does not exist in a bare checkout (`tools/install.sh` creates
it), so the pages keep the existing `./pxx` convention rather than inventing a new
one; the flags were exercised against the pinned binary the wrapper `exec`s.

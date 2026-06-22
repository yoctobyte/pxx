# Synapse library — proper compile check (Track B)

- **Type:** feature / investigation (library compat target)
- **Status:** backlog
- **Owner:** — (**Track B** — libraries/RTL; uses `$(PXX_STABLE)`, never rebuilds
  the compiler)
- **Opened:** 2026-06-22
- **Blocked-by:** feature-mimic-fpc
- **Why blocked:** needs the Track A `--mimic-fpc` / `{$MIMIC FPC}` curated
  FPC-3.2.2 define set; without it Synapse's `jedi.inc` picks the wrong platform
  branch (Kylix → `uses libc`) and the compile is meaningless. (NOTE 2026-06-22:
  `--mimic-fpc` has since LANDED — this ticket is now actionable.)
- **Relation:** the correctness/compat half of [[feature-networking]] (which
  names Synapse as compiler-compat target + test suite). Likely consumer of
  [[feature-mode-delphi-remaining]] (per-unit mode reset bites first in a
  multi-unit Synapse build) and RTL breadth. Companion driver to
  [[goal-compile-fpc-compiler]].

## Why this is Track B

The dialect/compiler side of consuming Synapse is largely done (Track A):
`{$mode delphi}` core, dotted unit names, `{$IF DECLARED}`, directive-if-numeric.
What remains to actually *compile* Synapse is **RTL availability and source
compat** — `Posix.*` shim units, `Classes`/`SysUtils` surface, `syncobjs`, the
blocking socket face — i.e. library work built with the pinned stable compiler.
So the activity belongs to Track B; genuine compiler/language gaps it surfaces
get filed back as Track A tickets.

## The task

Once `--mimic-fpc` lands (Track A), run a **proper** Synapse compile pass and
catalogue the blocker classes — this replaces the old ad-hoc directive-wall
probing with a real attempt:

1. Drive with `test/manual/try_synapse_compile.sh` and the `external/synapse`
   smoke units (start with the leaf units: `synautil`, `synaip`, `synacode`,
   then `blcksock`).
2. Build with `$(PXX_STABLE)` + `--mimic-fpc`. Do **not** rebuild the compiler.
3. For each failure, classify:
   - **RTL gap** (missing/short unit or routine) → fix in `lib/rtl` (our own
     from-scratch RTL, FPC naming — never port real FPC RTL; see the own-RTL
     strategy memory) or a `Posix.*` shim, and add a `make lib-test` smoke.
   - **Compiler/language gap** → file a focused Track A ticket (e.g. pull a slice
     from [[feature-mode-delphi-remaining]]); do not work around it in the lib.
4. Record the running blocker list + the furthest unit reached in
   [[feature-networking]] (or here), so progress is visible across sessions.

## Expectations / known edges

- **Per-unit `{$mode}` reset** is the prime first trap: `DelphiMode` is a
  whole-compile flag today, so a non-delphi unit pulled after a delphi Synapse
  unit inherits delphi semantics. If hit, pull that slice from
  [[feature-mode-delphi-remaining]] (Track A).
- DNS is not libc-blocked — reuse `synadns` over UDP (see networking strategy).
- Two-layer plan: our own transport (`net.pas`/`asyncnet.pas`, already landed for
  IPv4 loopback) under Synapse's reused protocol units (HTTP/FTP/SMTP).
- Mimic profile must stay opt-in; `lib/rtl` stays `{$ifdef FPC}`-clean.

## Done when

A defined Synapse subset (target: the blocking HTTP client path) compiles with
`$(PXX_STABLE) --mimic-fpc` and a smoke unit exercises it under `make lib-test`,
with every remaining gap either fixed in `lib/rtl` or filed as a Track A ticket.

## Recon 2026-06-22 (first `--mimic-fpc` pass, leaf units)

Ran `program p; uses <unit>;` per leaf with `--mimic-fpc` (fresh compiler).
mimic acceptance MET: every failure is now missing-RTL or a concrete
compiler gap, NOT a directive/branch error — units get past `jedi.inc` into the
FPC path. First blocker per unit:

- `synautil`, `synaip`, `asn1util`, `synachar` → **`uses` unit not found:
  `unixutil`** (RTL — Track B).
- `synsock`, `blcksock` → **`uses` unit not found: `dynlibs`** (RTL — Track B).
- `synacode` → **two Track A gaps, both since handled/filed:**
  1. capital `Array` keyword (`synacode.pas:344`) → FIXED (b5c0252).
  2. then `undefined variable (Move)` (`:359`) — `Move`/`FillChar` System
     primitives absent (RTL — Track B; provide in `lib/rtl`, or as compiler
     builtins).

Track A spinoff filed + FIXED: [[bug-var-open-array-fixed-arg-length]] (a `var
array of T` param got a wrong length from a static-array argument — var and
field, on `synacode`'s `ArrByteToLong`/MD5 path); also
[[bug-static-array-length-direct]] (1-D).

### Re-probe 2026-06-22 (after the Track A fixes) — Track A blockers CLEARED

Same leaf sweep with `--mimic-fpc` after the capital-`array` keyword fix
(b5c0252) and the var-open-array fixes. **Every remaining first-blocker is now
RTL** (no parse/codegen/dialect gap surfaces):

- `synautil` / `synaip` / `asn1util` / `synachar` → `uses` unit not found:
  **`unixutil`**.
- `synsock` / `blcksock` / `mimepart` / `mimemess` / `smtpsend` / `httpsend` /
  `ftpsend` → `uses` unit not found: **`dynlibs`**.
- `synacode` → `undefined variable (Move)` (its `uses` is satisfiable; stops on
  the **`Move`** System primitive). `FillChar` is the sibling.

So the Track A (compiler) side of the Synapse path is, for the leaf set, done for
now. The compiler no longer trips on Synapse dialect/parse/codegen.

**Track B next (RTL breadth, the gating units):**
1. `unixutil` — small POSIX util shim unit.
2. `dynlibs` — `LoadLibrary`/`GetProcAddress`/`UnloadLibrary` over the PAL
   dynlib surface (PXX_HAS_DYNLIB).
3. `Move` / `FillChar` — System memory primitives, auto-available without `uses`
   (compiler builtins, or an always-loaded RTL surface). NOTE: this one is a
   track-boundary call — if delivered as compiler intrinsics it is Track A; as an
   always-loaded RTL unit it is Track B. Decide before starting.

Once these land, re-run and record the next class (expected: `Classes`/`SysUtils`
surface depth).

---
prio: 45  # auto
---

# Synapse library — proper compile check (Track B)

- **Type:** feature / investigation (library compat target)
- **Status:** backlog
- **Owner:** — (**Track B** — libraries/RTL; uses `$(PXX_STABLE)`, never rebuilds
  the compiler)
- **Opened:** 2026-06-22
- **Note:** was blocked on `feature-mimic-fpc`; that landed 2026-06-22. Actionable.
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
3. `Move` / `FillChar` — System memory primitives, auto-available without `uses`.
   **Now unblocked for Track B as plain RTL functions:** untyped `var`/`const`
   parameters landed (Track A, [[feature-untyped-parameters]], aafd222), so these
   are writable in `lib/rtl` directly: `Move(const Source; var Dest; Count)` +
   `FillChar(var X; Count; Value: Byte)` over `@Source`/`@Dest`. Caveats: `Move`
   must be **overlap-safe** (memmove — copy backward when `dst>src` and ranges
   overlap; the internal `PXXMemMove` is forward-only/memcpy); `FillChar` needs a
   byte fill (only `PXXMemZero` exists). Auto-load so they resolve without `uses`.

Once these land, re-run and record the next class (expected: `Classes`/`SysUtils`
surface depth).

### Scoping 2026-06-22 (Synapse source installed)

Ran `tools/install_externals.sh` (geby/synapse @ 9c590c1, shallow clone into the
gitignored `external/synapse`). Scoped the gating `unixutil` blocker to size the
RTL shims — it is a **multi-unit chain**, not one small unit:

- `synautil.pas:81` FPC/Unix branch is `uses UnixUtil, Unix, BaseUnix;` — so
  "unixutil not found" is the first of three. Symbols `synautil` actually
  references from that chain: `TZSeconds` (from `UnixUtil`), `gettimeofday` /
  `fpgettimeofday` + `TTimeVal` (from `Unix` / `BaseUnix`). `synaip`, `asn1util`,
  `synachar` pull `unixutil` transitively via `uses synautil`.
- So the minimal unblock for the four leaf units is a small **`unixutil`** (just
  `TZSeconds`) **plus** `Unix`/`BaseUnix` shims providing `gettimeofday`/
  `fpgettimeofday`/`TTimeVal` (these can sit over PAL clock + raw syscalls). The
  `dynlibs` set (`synsock`/`blcksock`/…) additionally needs a PAL dynlib surface
  — note `PalHasDynlib` returns True on posix but **no `PalDlOpen`/`Sym`/`Close`
  primitives exist yet**, and a libc-free `dlopen` is a design decision (loader
  vs. link libc) — resolve that before `dynlibs`.

This is a deep RTL-breadth cascade (BaseUnix/Classes/SysUtils depth follows), so
it wants a dedicated push rather than opportunistic slices. The analysis above is
the starting point.

### Keystone 2026-06-22 — `dynlibs` gates the ENTIRE leaf path

Re-probing `uses synautil` on v38 (untyped params landed): first wall is still
`unixutil`, but `synautil` unconditionally `uses ... SynaFpc`, and **`SynaFpc`
itself `uses dynlibs`** (under `{$IFDEF FPC}`). So `dynlibs` is required even for
the "simple" leaf units (`synautil`/`synaip`/`asn1util`/`synachar`), not just
`synsock`/`blcksock`. `SynaFpc` needs only `TLibHandle` + `LoadLibrary` /
`FreeLibrary` / `GetProcAddress` / `GetProcedureAddress` / `UnloadLibrary` /
`NilHandle` — it wraps them; Synapse tolerates `LoadLibrary` returning the nil
handle (that path just means "optional lib, e.g. SSL, unavailable").

So an **honest minimal `dynlibs`** (FPC signatures; `LoadLibrary -> NilHandle`,
`GetProcAddress -> nil` until a real PAL loader exists) unblocks compilation and
the no-dynamic-lib (plain-HTTP, no-SSL) path. It is NOT a workaround for a
compiler bug — libc-free POSIX genuinely has no runtime loader; `PalHasDynlib`
returning True on posix is the actual inconsistency to fix (set it False, or add
real `PalDlOpen` over libc when a "link-libc" profile is chosen — a deliberate
design decision, file separately). Recommended order for the dedicated push:
`dynlibs` (stub) -> `unixutil`/`Unix`/`BaseUnix` -> verify `SysUtils`/`Classes`
depth. (Coordination: `Move`/`FillChar` are owned elsewhere on Track B; keep
`dynlibs`/the unix shims separate from them.)

### Progress 2026-06-24 — dynlibs + unix shims LANDED; blocked on a directive bug

Track B RTL landed (all with `make lib-test` smokes):

- **`lib/rtl/dynlibs.pas`** — honest stub (`LoadLibrary->NilHandle`,
  `GetProcedureAddress->nil`). Unblocks `SynaFpc` and thus every leaf unit's
  `uses`. Real loader split into [[feature-real-dynlib-loader]] (opt-in,
  syscall-first / libc-cheat policy). Carries a PChar-overload **workaround** for
  [[bug-pchar-to-string-implicit-conv]] (Track A) — remove when that lands.
- **`lib/rtl/baseunix.pas`** — `timeval` family + `fpgettimeofday` over a real
  CLOCK_REALTIME `clock_gettime` syscall (native-width timespec per arch).
- **`lib/rtl/unix.pas`** — `Tzseconds` (0/UTC; TZif parse deferred).
- **`lib/rtl/unixutil.pas`** — presence-only.

With these the `uses` chain of `synautil`/`synaip`/`asn1util`/`synachar` fully
resolves. **Furthest reached:** `synautil` now passes the uses clause and stops
at a **Track A compiler bug** — spurious `unterminated conditional directive` on
`synautil` + `jedi.inc` (jedi alone OK, synautil sans jedi OK, together fail).
Filed urgent: [[bug-conditional-directive-miscount-synautil]]. No lib workaround
(Platonic).

**Blocker stack now (leaf set):**
1. **[[bug-conditional-directive-miscount-synautil]]** (Track A, urgent) — gates
   synautil/synaip/asn1util/synachar at the directive phase.
2. After that: `synafpc`/`synautil` need **`StrLCopy`** (and likely sibling
   `strings`-unit routines) — RTL gap, Track B.
3. `Move`/`FillChar` — owned separately on Track B.

Also open from earlier: [[bug-hex-char-code-literal]] (Track A, urgent) for
`synacode`'s `#$NN` set constants.

### Progress 2026-06-24 (cont.) — synafpc COMPILES; StrLCopy/Sleep landed

- [[bug-hex-char-code-literal]] **FIXED by Track A** (v50). `synacode` now parses
  past its `#$NN` set constants and stops only at `Move`/`FillChar`.
- Added to `lib/rtl/sysutils.pas` (FPC `strings`/SysUtils surface): **`StrLCopy`,
  `StrLComp`** (synafpc's `SysUtils.StrLCopy`/`StrLComp` wrappers — FPC path, not
  kylix/posix), and **`Sleep`** (nanosleep syscall). Smoke: `test/lib_strpchar`.
- **`synafpc` now compiles fully (`ok`)** — the keystone unit is unblocked.

Leaf-set re-probe (v50, `--mimic-fpc`):

| unit | state |
|------|-------|
| `synafpc` | **OK** |
| `synautil`/`synaip`/`asn1util`/`synachar` | blocked on [[bug-conditional-directive-miscount-synautil]] (Track A) |
| `synacode` | needs `Move`/`FillChar` (RTL; intrinsic future = [[feature-move-fillchar-intrinsics]]) |
| `synsock`/`blcksock` | next gap: `uses` unit not found **`sockets`** (FPC Sockets unit — RTL, Track B) |

Spinoff bug filed while verifying the hex fix: [[bug-set-of-char-const-corrupts-char-codegen]]
(Track A, urgent) — a `set of char` typed constant corrupts `Ord(char-var)`
codegen; Synapse uses such constants, so it threatens correctness later.

**Track B next (not blocked on Track A):** `Move`/`FillChar` RTL, then the
`sockets` unit for synsock/blcksock.

### Progress 2026-06-24 (cont. 2) — sysutils breadth; synacode hits {$R-} at emit

Added to `lib/rtl/sysutils.pas` (all smoked in `test/lib_strpchar`):
**`Move`** (overlap-safe/memmove) + **`FillChar`** (interim home — see
[[feature-move-fillchar-intrinsics]]; FPC's is System/no-uses), **`IntToHex`**,
**`StringOfChar`**. synacode resolves all of these now.

**`synacode` new wall: `{$R-}` at emit** — [[bug-r-directive-toggle-treated-as-resource]]
(Track A, urgent). The `{$R}` lexer reads the range-check toggle `-`/`+` as a
resource filename; the error only fires at emit, so it was masked until synacode
started passing semantics. Latent since 2026-05-30, not a v50 regression.

Spinoff: const-string-index quirks folded into
[[bug-set-of-char-const-corrupts-char-codegen]] (untyped string const index →
garbage char, worked around in IntToHex; typed `const s: string = ...` → parse
error).

**Track A urgent queue now (all block Synapse):**
1. [[bug-conditional-directive-miscount-synautil]] — synautil/synaip/asn1util/synachar.
2. [[bug-r-directive-toggle-treated-as-resource]] — synacode (and the above, at emit).
3. [[bug-set-of-char-const-corrupts-char-codegen]] — correctness.

**Track B (not blocked):** `sockets` unit → synsock/blcksock (+ our own net lib /
HTTP, async-aware — see the design note to come).

### Re-probe 2026-06-24 (cont. 3) — sockets unit advanced synsock; new gaps

Leaf/socket/protocol sweep (v53, `--mimic-fpc`, all current RTL):

| unit | state |
|------|-------|
| `synafpc` | OK |
| `synautil`/`synaip`/`asn1util`/`synachar` | [[bug-conditional-directive-miscount-synautil]] (Track A) |
| `synacode` | [[bug-r-directive-toggle-treated-as-resource]] at emit (Track A) |
| `synsock`/`blcksock`/`httpsend`/`ftpsend`/`smtpsend` | advanced past `sockets` (unit now exists) → next: `termio` (added, trivial), then **[[bug-unit-qualified-constant-not-resolved]]** (Track A) on ssfpc's `FIONREAD = termio.FIONREAD;` |

Track B added `lib/rtl/termio.pas` (FIONREAD/FIONBIO/FIOASYNC). After the
qualified-const bug clears, the next RTL gaps for the socket path are the
`sockets` address-string helpers (`StrToNetAddr`/`NetAddrToStr`/`HostToNet`/IPv6
variants) and a `netdb` shim (`THostEntry`/`GetHostByName`/`ResolveName`/`+6`/
`TProtocolEntry`/`TServiceEntry`, over `lib/rtl/dns`), then `Classes` depth
(TStream — itself Track-A-blocked). `syncobjs` already exists.

**Synapse is now heavily Track-A-gated**: directive-miscount, R-toggle,
qualified-const (+ string-cmp / Read-Write-names / untyped-method-params for the
Classes it needs). Track B shim work past synsock waits on the qualified-const fix.

### Re-probe 2026-06-25 (v55) — {$R-} fixed; synacode COMPILES + partially runs

`{$R-}` fix (v55) + all the RTL/compiler fixes mean **synacode now compiles
fully**, joining `synafpc`. Leaf set:

| unit | state |
|------|-------|
| `synafpc`, `synacode` | **compile OK** |
| `synautil`/`synaip`/`asn1util`/`synachar` | [[bug-conditional-directive-miscount-synautil]] (Track A, open) |
| `synsock`/`blcksock` | [[bug-unit-qualified-constant-not-resolved]] (`termio.FIONREAD`, Track A, open) |

**synacode functional dogfood** (`--mimic-fpc`): `EncodeBase64('hello world')` =
`aGVsbG8gd29ybGQ=` — **correct**. But `DecodeBase64` returns garbage and `MD5`
segfaults at runtime — both index/process const lookup tables
(`ReTableBase64`, the MD5 state), so this is the const-table-index / managed-Move
runtime codegen family ([[bug-set-of-char-const-corrupts-char-codegen]] and
relatives). Compiling is necessary but not sufficient — synacode needs those
runtime codegen bugs fixed (Track A) for correct Base64-decode/MD5. A minimal
repro from synacode's `Decode4to3Ex` / MD5 path would sharpen the Track A ticket.

Two leaf units down (compile); the rest gated on directive-miscount /
qualified-const, and full synacode correctness on the const-codegen runtime bugs.

### Re-probe 2026-06-28 (v83) — prior Track A gates cleared; two new bugs found

All previously open Track A blockers are now in `done/`:
[[bug-conditional-directive-miscount-synautil]], [[bug-unit-qualified-constant-not-resolved]],
[[bug-set-of-char-const-corrupts-char-codegen]], [[bug-proc-typed-call-const-record-arg]].

Fresh probe at v83 with `--mimic-fpc`:

| unit | state |
|------|-------|
| `synafpc`, `synacode` | **compile OK** (unchanged) |
| `synautil`/`synaip`/`asn1util`/`synachar` | **[[bug-chr-builtin-shadows-param-name]]** (Track A, new) — `CountOfChar(…; Chr: char)`: `Chr` treated as built-in, rejected as param name |
| `synsock`/`blcksock`/`httpsend` | **[[bug-consteval-named-type-cast]]** (Track A, new) — `ssfpc.inc`: `INVALID_SOCKET = TSocket(NOT(0))` fails ConstEval |

Both bugs filed 2026-06-28. When Track A fixes them, re-probe to find the next wall.

## TRIAGE (2026-06-30, multi-agent verify)

UPDATE (verify): both listed Track A blockers (bug-chr-builtin-shadows-param-name, bug-consteval-named-type-cast) are now in done/. Re-probe 'uses synautil --mimic-fpc' advances past them to a NEW wall: 'too many array constant elements' (candidate focused Track A ticket / capacity bump). Track B compile target still open.

### Re-probe 2026-07-11 (v201, opus-night)
`uses synautil --mimic-fpc` now dies at jedi.inc: PXX evaluates `{$...}`
directives inside `(* ... *)` comments, and jedi.inc's big doc comment
(lines 48-699) contains example directives with `14.2` float literals →
"unexpected character" (misreported at synautil.pas:458 via the include
splice). Same lexer bug the New-ZenGL ladder hit the same night —
[[bug-pascal-directive-inside-paren-star-comment]], prio raised to 65 since
it walls BOTH corpora. Without --mimic-fpc the probe instead takes the
Kylix path and stops at `uses libc` (expected). Next wall after the lexer
fix is presumably the previously-noted "too many array constant elements".

---
track: A
prio: 25
type: feature
blocked-by: []
summary: "Get host paths out of the compiler and into config. FOUR slices landed: -I/-Fu search roots (2026-06-20), pxx.cfg tier 3 (2026-08-21), the /usr/include fallback as a discovered TABLE (2026-08-26), and per-directory library manifests -- pxxlib.cfg supplying define/undef/mode to units under one tree and nothing else (2026-08-31), which was the load-bearing one and is what makes PasApplyMimicDefines's NEVER-during-a-self-build landmine structural. DEMOTED 55 -> 25 on 2026-08-31: all three remaining bullets lack a named consumer and two are partly superseded by work that landed AFTER they were written (soname DISCOVERY is done; the /usr/include table is now discovered, not hardcoded). Do not take this for its title - the big half is landed."
status: backlog
owner: frankS
---

# Dynamic Include Paths, Configuration Files, and System Scanner

- **Type:** feature
- **Status:** working
- **Owner:** frankS
- **Opened:** 2026-06-14 (from ESP-IDF auto-import analysis)

## Motivation

Avoid hardcoding host system search paths in the compiler (`parser.inc` and `cpreproc.inc`). Provide command-line include flags, support configuration files for targets and libraries, and create a scanner tool to automatically discover and map SDKs/libraries (including ESP-IDF and host system libraries) without baking locations into the compiler.

## Scope

- **Compiler Option:**
  - Support `-I<dir>` command-line arguments to dynamically add directories to the C preprocessor include paths and unit search paths.
- **Configuration File:**
  - Support reading a default config file (e.g., `pxx.cfg` or `frankonpiler.json`) from the current working directory or executable directory.
  - The configuration file will list include directories, active preprocessor defines, and target profile maps.
- **Refactoring Search Path Logic:**
  - Refactor [parser.inc](file:///home/rene/frankonpiler/compiler/parser.inc#L6560) and [cpreproc.inc](file:///home/rene/frankonpiler/compiler/cpreproc.inc#L1014) to eliminate hardcoded paths (e.g., `/usr/include`, `/usr/include/gtk-2.0`).
  - Search paths should loop dynamically over paths loaded from command-line arguments and configuration files.
- **System Scanner Tool (`tools/pxx-scan`):**
  - Write a standalone script/utility (e.g., Python or shell) that:
    - Probes standard host locations (Linux header paths, local GCC/clang include paths).
    - Probes Espressif toolchains and ESP-IDF paths using environment variables like `$IDF_PATH`.
    - Generates a local `pxx.cfg` file with the resolved search paths matching the selected target profile.
- **Dynamic Library Mapping:**
  - Move hardcoded system library mapping rules (e.g. `uses sqlite3` mapping to `libsqlite3.so.0`) into the configuration file layout.

## Non-goals

- Dynamic package download manager or dependency updates (outside compiler scope).

## Acceptance

- Compiler compiles C unit imports using `-I <path>` directories:
  ```sh
  ./pascal26 -I/home/user/esp/esp-idf/components/driver/gpio/include main.pas
  ```
- Removing hardcoded `/usr/include/` from the compiler source code does not break local testing as long as the search path is provided via command-line or a loaded `pxx.cfg`.
- The scanner script successfully outputs a valid config file for both a hosted Linux environment and an ESP-IDF environment.

## Per-library scoped configuration (added 2026-06-19)

Beyond a global `pxx.cfg`, support **per-directory library manifests** so a
library's compile settings (defines, undefs, dialect mode, include paths) apply
**only to units under that library's folder tree** — never virally to the user's
program or to sibling libraries. This is the general mechanism for compiling any
third-party Pascal library that needs a different define/mode profile (Synapse,
IDF, GTK, …) without CLI flags each time and without editing the library source.

**Load-bearing primitive — per-unit define-scope save/restore keyed to the unit's
source directory:**

```
on begin-compiling unit U (path P):
    push define-state
    find nearest-ancestor manifest of P   (e.g. lib/synapse/pxxlib.cfg)
    apply its defines / undefs / mode / include paths
    ... compile U ...
    pop define-state
```

Because the scope follows the **unit being compiled** (its own directory), not
the caller, cross-`uses` is automatically clean: a Synapse unit using our RTL and
our code using Synapse each compile under their own directory's manifest. Sibling
libraries never see each other's defines. The user's program (no manifest above
it) keeps the base/command-line defines untouched.

**Manifest = a small per-library build profile** in the library root, e.g.
`lib/synapse/pxxlib.cfg`:

```
define   POSIX
define   LINUX
define   UNIX
undef    FPC          # not-FPC selects Synapse's Delphi-Posix branch AND dodges
                      # the {$ifdef FPC}=real-FPC landmine — scoped, so it can't
                      # leak into our own code in the same build
mode     delphi       # the @-operator relax (see feature-mimic-fpc)
incpath  .
```

- Ship hand-written manifests for known libraries (Synapse as the first special
  case — "just works", no CLI). The `tools/pxx-scan` scanner generates them for
  discovered SDKs (IDF include trees, `/usr/include/gtk-2.0`, …).
- Nearest-ancestor manifest wins; caching per directory.

**Relationship to feature-mimic-fpc:** this supersedes the global `--mimic`
define-profile idea. The Synapse define set becomes a scoped manifest, which is
strictly better — the viral-leak / FPC-define-landmine worry disappears because
`undef FPC` only applies under `lib/synapse/`.

**Cost:** (1) stackable define scope (push/pop), (2) resolver tracks the current
unit's directory + nearest-ancestor manifest lookup, (3) a tiny manifest parser.
Medium, but it is the general solution for ALL third-party libs, not a one-off.

## Log
- 2026-06-20 — **Pascal-`uses` search-path slice landed (commit 723001c).**
  Added an ordered Pascal-unit search list (`PasUnitDirs`, defs.inc; `AddPasUnitDir`,
  cpreproc.inc), fed by `-Fu<dir>` (FPC-style) and `-I<dir>` (now feeds BOTH the
  C `#include` path and the Pascal-unit path). `LoadUnit` (parser.inc) searches
  these roots after the including file's own directory and before the
  compiler-anchored builtin/RTL/LCL dirs, so a project or per-platform dir (e.g.
  `lib/rtl/platform/posix/`) can supply or override a unit by name with no ifdefs
  in callers — the PAL backend-selection mechanism. Deduped + trailing-'/'
  normalised. test/test_unitpath.pas + same-named posix/esp backends prove
  selection; in test-core. Gate green (make test byte-identical + cross-bootstrap
  + cross suites). This is the slice feature-platform-abstraction-layer needed;
  it replaces the interim single-`{$ifdef}` switch. STILL OPEN here: `pxx.cfg`
  config file, per-directory library manifests (scoped define/mode/incpath),
  `tools/pxx-scan`, dynamic system-library soname mapping.
- 2026-06-20 — First slice landed (C-include search path). `-I<dir>` flag →
  ordered `CIncludeDirs` list (defs.inc), searched after the including file's own
  directory and before system dirs. The hardcoded `/usr/include…/clang` fallback
  chain in `cpreproc.inc` is now gated to native (`TargetArch = TARGET_X86_64`)
  so cross targets never pull host headers. This resolves
  `bug-c-quoted-include-search-path` (moved to done) and gives candidate C libs a
  project include-root mechanism. STILL OPEN here: `pxx.cfg` config file,
  per-directory library manifests (the scoped define/mode/incpath primitive),
  `tools/pxx-scan` scanner, Pascal-unit (`uses`) search-path refactor, and
  dynamic system-library soname mapping. The `-I` plumbing + native gate are the
  shared foundation those build on.


---

## 2026-08-19 — the Synapse justification is WITHDRAWN; rank this on self-build safety

[[decide-what-synapse-actually-needs-vs-mimic-fpc]] is closed, and with it the case this
ticket was most often cited for. Owner, 2026-08-17: *"We already implemented our own TCP
stack, including SSL. Synapse is a TEST library, not something we will build on in
practice."* Scoped manifests **must be justified by a library we DO build on, or by the
self-build safety argument, never by Synapse.**

**Prio left at 45 on purpose — the justification changed, not the value.** The surviving
argument is the stronger one:

`PasApplyMimicDefines` (`compiler/lexer.inc:876`) carries the rule *"NEVER call during a
self-build — the compiler's own `{$ifdef FPC}` means real FPC, not PXX."* That is a
landmine enforced by remembering. Directory scoping makes it **structural**: a manifest
under `external/synapse/**` cannot reach `compiler/**`, so the hazard stops being
reachable rather than stopping being stepped on. Same shape as the uses-never-leaks
principle.

Other named manifest consumers from the original design — IDF, gtk, usr-include — are
unaffected and are ordinary justifications. Synapse may still be listed as a *user*; it
just cannot be the reason.


---

## 2026-08-21 — the `pxx.cfg` slice landed; manifests and the scanner are what remain

Tier 3 of the search-path order now exists, and the whole order is inspectable:

    -Fu / -I  >  PXX_HOME / PXX_LIBPATH  >  pxx.cfg  >  exe-dir defaults

`pxx --where` (landed the same night under `feature-toolchain-cli-ux`) prints all
four as RESOLVED, each root marked `[MISSING]` when it does not exist, by calling
the same routines a real compile calls. That is the half of this ticket that made
the rest debuggable: the original complaint was hardcoded paths, but the cost was
always that a path resolving to *nothing* reported itself as a hundred missing
symbols far from the cause.

**What `pxx.cfg` accepts:** `home <dir>` (an install root, exactly like
`PXX_HOME`), `unitpath <dir>`, `incpath <dir>`. `#` and `;` comment to end of
line.

**Where it is looked for**, first one that exists wins — `$PXX_CONFIG`, then
`./pxx.cfg`, then `~/.config/pxx/pxx.cfg`, then `<exe dir>/pxx.cfg`. One file
wins rather than merging four, because a merge makes "where did this path come
from" answerable only by knowing an order. `$PXX_CONFIG` naming a file that
cannot be read WARNS instead of silently falling through to a different config
file — the wrong config file is the hardest kind of wrong to see.

**Unknown / argless directives warn with `file:line` and compilation continues.**
A config file is read by a binary the user did not build, so a newer file must
still work on an older `pxx`; but silence is how a typo'd `unitpaths` costs an
afternoon.

Verified end to end, not reasoned: a compiler copied to a directory with no
libraries above it compiles a program that needs the RTL (via `home`) *and* a
project unit reachable only via `unitpath`. Rows in `test-quick` lock all of it,
including that the env tier outranks the file tier, and that the same source
compiled with and without a config in effect emits **identical bytes** (the
config tier is a third door onto `bug-a-the-compilers-output-depends-on-argv0`).

### Deliberately NOT in this slice
`define` / `undef` / `mode` in `pxx.cfg`. Those are the per-directory library
manifest above, and their entire value is that they are **scoped to a library's
own tree** — a global define switch is the viral-leak shape the manifest design
exists to avoid, and shipping one here first would turn the scoped version into
a migration instead of a design. The `PasApplyMimicDefines` landmine ("NEVER
call during a self-build") is still enforced by remembering.

### Still open
- Per-directory library manifests (`pxxlib.cfg`): the stackable define scope,
  nearest-ancestor lookup, the manifest parser. **This is the load-bearing one.**
- `tools/pxx-scan` (probe host / IDF trees, emit a config).
- Dynamic system-library soname mapping (`uses sqlite3` -> `libsqlite3.so.0`)
  out of the compiler and into config.
- ~~The hardcoded `/usr/include...` fallback chain in `cpreproc.inc`~~ — now a
  TABLE, see the 2026-08-26 entry below. Still native-gated, still spelled in
  the source; but it is data a config tier can extend rather than control flow.


---

## 2026-08-26 — tier 4 is a table, and two of its entries were searching nothing

The `/usr/include...` fallback was **sixteen copy-pasted five-line blocks**, each
differing only by a literal path and a **hand-counted string length**. It is now
one table (`CSysIncludeDirs`, filled by `BuildCSysIncludeDirs`) walked by one
loop, and `pxx --where` prints it as the fourth tier — so the whole search order
is now inspectable end to end, which was the half of this ticket that made the
rest debuggable.

**The bug that was hiding in there.** Two of the sixteen named a compiler
VERSION directory:

    /usr/lib/gcc/x86_64-linux-gnu/13/include/
    /usr/lib/llvm-18/lib/clang/18/include/

Both were stale on this box — gcc is 15 here — so **both entries had been
searching a directory that does not exist**, for however long, in silence. A
hardcoded version is a fallback that expires. They are now DISCOVERED by
scanning the parent directory, and every installed version is added rather than
a "newest" pick, which would need a version COMPARE (string order puts `9` after
`15`) for no gain — these are freestanding headers, near-identical across
versions.

**Behaviour is unchanged, checked against the pinned compiler rather than
reasoned:** the same host-only header (`<linux/limits.h>`) resolves to the same
value with the same single warning under both binaries; a root PAST entry 0
(`<glib/gtypes.h>`, table entry 3) resolves with zero host warnings under both,
because the warning is deliberately scoped to the bare `/usr/include/` entry —
the library roots below it have no pxx-shipped twin to be confused with.
`-nostdinc` still refuses the lot.

**Locked in `test-quick`** (the `cliux` recipe, beside the pxx.cfg rows): the
tier prints; both gates (`-nostdinc`, and a cross target) say *not searched* AND
print no roots underneath; and **no versioned root is `[MISSING]`** — a scanned
root exists by construction, so that assertion fires exactly when a hardcoded
version comes back. Each new row was verified to FAIL with its bug re-introduced
(gcc-13 literal injected, rebuilt, row went red, reverted), because a row that
cannot fail is not coverage.


---

## 2026-08-31 — per-directory manifests landed; this was the load-bearing slice

`pxxlib.cfg` in a library root now supplies `define` / `undef` / `mode` to every
unit under that tree and to nothing else.

**The primitive the design called for already existed.** The 2026-06-19 design
specified a stackable define scope keyed to the unit being compiled, and costed
it as the expensive third of the work. `ParseUsesUnitBody` has had exactly that
since `bug-pascal-defines-leak-across-units` — a full snapshot of
Active/HasValue/Value + Count/CharLen before a unit is lexed, restored after it
is parsed — and `CaseSensitiveMode`, `NestedComments`, `DelphiMode` and
`PyExprMode` are saved beside it for the same reason. So the manifest needed no
new unwind path at all: **apply it immediately after those saves and the
existing restore already covers it.** That is the whole reason it goes in there
and not at the search-path tier, and it is why this slice is small.

What was actually written: a nearest-ancestor walk with a per-directory cache
(`PxxLibFindManifest`), a line parser modelled on `PxxCfgApplyLine` but
deliberately not shared with it (that one appends `/` to every argument because
all of its arguments are directories; these are names), and one call site.

**The walk stops before the current working directory.** `lib/rtl/` probes
`lib/rtl/` and `lib/` and stops — a `pxxlib.cfg` in whatever directory `pxx`
happens to be invoked from is not an ancestor of anything, and letting it act
like one would be a global define switch wearing a scoped name.

### What is asserted, and the control

`test/test_libmanifest.pas` (in `test-core`) has three populations and **the two
negative ones are the test** — a manifest that leaked would pass a check of the
first line alone:

| | sees |
| --- | --- |
| unit under `test/libmanifest/` (one directory BELOW the manifest) | the manifest's define, and has LOST a `-dPROGDEF` the command line gave the build |
| a sibling library with no manifest | neither |
| the program itself | its own `-d`, and has never heard of the manifest's define |

The `mode` half is asserted through an observable rather than a flag: the
library unit contains `f := Double_` with no `@`, which compiles **only** under
`{$mode delphi}`. With the manifest moved aside the unit does not compile at all
(`error: undefined variable (Double_)`), verified — so the row can fail, and it
fails loudly rather than by one changed word.

The manifest carries an unknown directive on purpose and the row greps for the
warning: a manifest is read by a binary its author did not build, so a newer file
must still work on an older `pxx` — but not in silence.

### Deliberately not in this slice

`incpath` / `unitpath` inside a manifest. Those need the search-path lists
push/popped too, which is a second unwind path with no existing owner, and the
justification this slice rests on (the `PasApplyMimicDefines` self-build
landmine) is about defines and mode, not paths. They fall into the
unknown-directive warning today, which names the set this `pxx` knows.

### Still open

- `tools/pxx-scan` (probe host / IDF trees, emit a config).
- Dynamic system-library soname mapping (`uses sqlite3` -> `libsqlite3.so.0`).
- `incpath` / `unitpath` in a manifest, per above.

---

## 2026-08-31 — demoted 55 -> 25, because the title still prices the whole feature

The ranker kept offering this at 55 to every idle Track A agent after the
load-bearing slice landed, which is the stale-metadata failure this repo has a
name for: **the ticket's TITLE is still the big one, so it ranks at the value the
whole feature had rather than the value of what is left.** Each remaining bullet,
checked rather than assumed:

- **`tools/pxx-scan`.** Its host half is now redundant, and this is measured, not
  argued: `pxx --where` on this box resolves every library root and prints
  `/usr/lib/gcc/x86_64-linux-gnu/15/include/` — **discovered** by scanning the
  parent directory, on a box where the previously hardcoded `13` was stale (the
  2026-08-26 slice). A generated `pxx.cfg` would restate what the compiler
  already finds. Its IDF half overlaps `tools/install_esp32_target.sh`, which
  already locates the toolchain. **Needs a named consumer before it is worth
  writing.**
- **Dynamic soname mapping into config.** Largely superseded:
  `feature-dynamic-soname-discovery` is in `done/` (2026-08-21) and reads
  `/etc/ld.so.cache` directly, so an unmapped library already resolves to its
  real versioned soname. What is left is moving the static FALLBACK table
  (`CSonameForStem`, pasparser_proc.inc) into config, and that fallback now fires
  only when the cache misses.
- **`incpath` / `unitpath` inside a manifest.** Needs the search-path lists
  push/popped, which is a second unwind path with no existing owner — the define
  slice needed none, which is exactly why it was cheap — and the hazard it would
  close is much milder than the one the define slice closed. An unused include
  root costs nothing; a leaked define changes what compiles. **No named
  consumer.**

**None of this says the remaining work is wrong — it says it is worth 25.** If a
consumer appears (an IDF build that actually needs generated paths, a library
whose headers need a scoped `incpath`), raise it back and say which.

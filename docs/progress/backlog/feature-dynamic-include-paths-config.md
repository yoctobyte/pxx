# Dynamic Include Paths, Configuration Files, and System Scanner

- **Type:** feature
- **Status:** backlog
- **Owner:** —
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

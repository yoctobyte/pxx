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

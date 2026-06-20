# C quoted includes do not search the including file directory

- **Type:** bug (C frontend / include resolver)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-20
- **Relation:** surfaced by `library_candidates/tiny-regex-c` and
  `library_candidates/freebsd-regex`; blocks useful C-source library candidate
  testing before deeper C-body frontend work.

## Symptom

Running pinned stable v14 over candidate C sources fails to find headers that are
present next to the source file:

```text
stable_linux_amd64/default/pinned library_candidates/tiny-regex-c/tests/test1.c /tmp/t
pascal26:1: error: C include file not found (/usr/lib/llvm-18/lib/clang/18/include/re.h)
```

`library_candidates/tiny-regex-c/re.h` exists. Running from the candidate
directory still fails for `tests/test1.c`, so quoted include resolution is not
using the including file's directory and/or project-relative include roots before
falling back to the Clang resource include path.

FreeBSD regex shows the same class of issue for local/private headers such as
`utils.h` in helper files, although some headers like `collate.h` may be genuine
FreeBSD-private dependencies missing from the imported subset.

## Expected search order

For `#include "name.h"`:

1. Directory of the file containing the include.
2. Explicit/project include directories, once such configuration exists.
3. Existing system fallback directories.

For `#include <name.h>`, keep system-oriented behavior, but project include dirs
may still be useful for candidate-library builds.

## Acceptance

- `library_candidates/tiny-regex-c/tests/test1.c` finds `../re.h` or equivalent
  local/project include path without falling directly to the Clang resource dir.
- A minimal nested include regression test proves that `"local.h"` resolves
  relative to the including file, not only the process CWD.
- Existing C import tests still pass.

## Log
- 2026-06-20 — Opened after candidate regex smoke runs. The Clang path in the
  diagnostic is a fallback symptom, not evidence that the libraries depend on
  Clang headers.
- 2026-06-20 — Resolved (search-path slice of feature-dynamic-include-paths-config).
  Findings + fix:
  - #1 (including file's own directory) was ALREADY correct — `CPInclude` threads
    `GetFilePath(CPrepPath)` (the resolved dir of each include) as the `baseDir`
    for that file's own nested includes, so `"local.h"` resolves relative to the
    including file, not the CWD. Added a regression test proving it
    (`test/cinc/cinc_local.h` via baseDir).
  - #2 (project include roots) implemented: new `-I<dir>` flag → ordered
    `CIncludeDirs` list, searched after the including file's dir and BEFORE any
    system dir (so a project's own header — e.g. our own `zlib.h` — wins over a
    host one). tiny-regex-c now resolves with `-I library_candidates/tiny-regex-c`.
  - Cross-platform correctness: the hardcoded `/usr/include…/clang` fallback
    chain is now gated to native (`TargetArch = TARGET_X86_64`) only — those are
    host headers, wrong for any cross target; cross builds resolve solely from
    the including-file dir + `-I` roots.
  - Test `test/cinc/cinc_main.c` (same-dir `+` `-I` include) wired into test-core
    with `-Itest/cinc/inc`. commit reference (board checker): see the
    feature-dynamic-include-paths-config slice commit.
  - Remaining (config-file / `pxx.cfg` / per-dir manifest form of "project
    include dirs") stays tracked in feature-dynamic-include-paths-config.

---
slug: feature-n-a-c-header-import-cannot-name-a-header-in-a-subdirectory
track: N
prio: 45
type: feature
status: working
owner: frankB
created: 2026-09-08
found-by: frankuser
tags: [nilpy, ffi, headers, imports, lekkerzeilen]
blocked-by: []
summary: "`import sqlite3` reaches /usr/include/sqlite3.h, but nothing reaches /usr/include/SDL2/SDL.h by a bare name: `import SDL2/SDL.h`, `import SDL`, `from SDL2 import SDL` and `import SDL2_SDL` all answer `no unit named ...`. The absolute quoted form `import \"/usr/include/SDL2/SDL.h\"` DOES work, so this is ergonomics and portability rather than capability -- but an absolute path hardcodes a distribution layout into the source, which is exactly what a showcase must not do. Measured 2026-09-08 against compiler/pascal26 a7b03135f504."
---

# Measured

| spelling | result |
| --- | --- |
| `import sqlite3` | OK — flat header in /usr/include |
| `import SDL2/SDL.h` | `no unit named sdl2` |
| `import SDL` | `no unit named sdl` |
| `from SDL2 import SDL` | `no unit named sdl2` |
| `import SDL2_SDL` | `no unit named sdl2_sdl` |
| `import "/usr/include/SDL2/SDL.h"` | **works** (then hits the `=Q` asm gap) |
| `import "SDL2/SDL.h"` | resolves RELATIVE to the source dir, not the include path |

The quoted form already parses and already has a resolution path; what it lacks
is the include-path search that the bare form has. `import "SDL2/SDL.h"` looking
in `/usr/include` after the source directory would be the whole feature, and it
is the spelling a C programmer would already write.

# Why it matters for more than tidiness

`lekkerzeilen/platform/_pxx.py` — a stub its own author wrote for this — plans
`import SDL2/SDL.h`. An absolute path works but bakes `/usr/include` into the
source, so the file stops being portable and stops being a fair demonstration.
The showcase value is a Python program that compiles; a Python program that
compiles *on this distribution* is a weaker claim.

Note the name-collision rule already settled next door: a Python stdlib name
that also names a C header (`string`, `math`) must reach the Python module
first — see `test_nilpy_import_c_header_still_works.npy`, which guards the
ORDER. Any change here must keep that ordering.

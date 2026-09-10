---
slug: bug-n-a-c-header-import-lowercases-the-library-name-so-gl-does-not-link
track: N
prio: 50
type: bug
status: working
owner: frankB
created: 2026-09-08
found-by: frankuser
tags: [nilpy, ffi, headers, linking, lekkerzeilen]
blocked-by: []
summary: "`import \"/usr/include/GL/gl.h\"` compiles and links, and the binary then dies at RUNTIME with `libgl.so: cannot open shared object file`. The library on disk is `libGL.so.1` -- the import derives a soname from the header stem and loses the case. Measured 2026-09-08 against compiler/pascal26 a7b03135f504. THE COMPILE IS GREEN AND THE FAILURE IS AT EXEC, which is the bad shape: nothing in the build says anything is wrong."
---

# Repro

```
$ printf 'import "/usr/include/GL/gl.h"\nprint(glGetError())\n' > g.py
$ ./compiler/pascal26 g.py out          # compiles; two host-header warnings only
$ ./out
./out: error while loading shared libraries: libgl.so: cannot open shared object file
```

On disk: `/usr/lib/x86_64-linux-gnu/libGL.so`, `libGL.so.1`, `libGL.so.1.7.0`.

Note `import "/usr/include/GL/gl.h"` with only `print("reached")` **runs fine** —
the missing library is only reached when a symbol from it is actually called, so
the trivial probe passes and the real one fails.

# Why this is more than a `tolower` bug

`sqlite3.h` -> `libsqlite3.so.0` works, which is what makes the rule look sound:
the stem happens to be lowercase there, so **the sample that confirms the rule is
the one where case cannot matter.** A header stem is not a soname in general
(`GL/gl.h` -> `libGL.so.1`, `SDL2/SDL.h` -> `libSDL2-2.0.so.0`), so the mapping
wants the real mechanism — `pkg-config`, an explicit table, or a declared name —
rather than a case fix.

**Whatever replaces it, keep the failure at LINK time rather than exec time.**
A green compile that dies on startup is the worst of the three outcomes.

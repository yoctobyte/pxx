---
slug: feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym
track: N
prio: 50
type: feature
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, ffi, headers, linking, soname, lekkerzeilen, sdl]
blocked-by: []
summary: "For a header in a SUBDIRECTORY, the directory names the library far better than the file does: measured 2026-09-10 across /usr/include's 2542 subdirectory headers, the FILE stem resolves for 76 and the DIRECTORY name resolves for 617 more (EGL/eglext.h -> libEGL.so.1, FLAC/stream_decoder.h -> libFLAC.so.14). It cannot be added as a plain fallback, and the counterexample is measured, not feared: `net/if.h` is a glibc header and `libnet.so.9` is an unrelated packet-crafting library that IS installed -- so a directory-derived guess there passes the existing missing-library guard, links, loads, and dies on `undefined symbol`, which is worse than the loud failure that guard was added for. What makes it safe is the same file-parsing capability the ld.so.cache reader already proved: read the candidate .so's .dynsym and require that it actually EXPORTS the symbols the header declares. That upgrades the guard from `does this library exist` to `does this library answer`, catches net/if.h, and is what SDL2 (libSDL2-2.0.so.0, which no name-shaped rule reaches) needs."
---

# Two halves, and only the second one makes the first safe

## Half 1 — the directory is the better key, by 8x

Measured 2026-09-10 on this box, over every `.h` in a `/usr/include`
subdirectory, resolving `lib<key>.so.` against `/etc/ld.so.cache` (exact, then
case-insensitive, which is what the compiler does today):

| | headers |
| --- | --- |
| the FILE stem resolves | 76 |
| the file stem fails and the DIRECTORY resolves | **617** |
| neither resolves | 1849 |
| total | 2542 |

This is not a surprise once stated: a subdirectory under `/usr/include` is
usually the PACKAGE, and the package is the library. The file is a component of
it. `GL/gl.h` resolving off its file stem at all is a coincidence — `gl`
case-insensitively matches `GL` — and it is the coincidence the sibling ticket
`bug-n-a-c-header-import-lowercases-the-library-name-so-gl-does-not-link` was
filed about, which is why that one looked like a case bug.

## Half 2 — why it cannot ship alone, with the counterexample

Checked the directory names that are NOT libraries — `sys`, `bits`, `linux`,
`asm`, `arpa`, `netinet`, `x86_64-linux-gnu`, `gnu`, `rpc`, `scsi` and eleven
more. All correctly resolve to nothing. **Two do resolve:**

| directory | resolves to | verdict |
| --- | --- | --- |
| `drm/` | `libdrm.so.2` | correct |
| `net/` | `libnet.so.9` | **wrong, and it is installed** |

`/usr/include/net/if.h` and `net/route.h` are glibc headers; their symbols are in
libc. `libnet` is a packet-crafting library that happens to occupy the name.

That single row is disqualifying, and the reason is about the FAILURE MODE rather
than the hit rate. The bug this would be built on top of fails LOUDLY at exec:
`libgl.so: cannot open shared object file`. A directory-derived wrong answer
fails QUIETLY — the library exists, so it passes the
`CSynthMissingLibs` guard in `RegisterExternal`, links, loads, and dies on
`undefined symbol` in a library the user never named. **Trading a loud failure
for a quiet one is a regression even when it is right 617 times out of 619.**

## What makes it safe, and it is a capability we already have

The compiler cannot execute `pkg-config`, but it does not need to: it already
parses `/etc/ld.so.cache` as a plain file to answer "what is this box's soname
for X". A `.so`'s `.dynsym` is the same kind of read, and `/etc/ld.so.cache`
hands over the resolved PATH beside every key — the reader currently discards it
(*"We want the key only: the compiler emits a DT_NEEDED name, it never opens the
library"*), which is exactly the value this needs.

So: for each candidate library, require that it EXPORTS the symbols the header
declares. Then the ranking is by evidence rather than by name shape, and the
guard upgrades from **"does this library exist"** to **"does this library
answer"** — a strictly stronger question at the same choke point.

It also catches things no naming rule can. `SDL2/SDL.h` needs
`libSDL2-2.0.so.0`, which is reachable from neither `SDL` nor `SDL2` by any
prefix rule (`libSDL2.so.` does not match `libSDL2-2.0.so.0`), and IS reachable
by asking which installed library exports `SDL_Init`.

## Cost, honestly

Reading a `.dynsym` means ELF section-header walking — more than the 24-byte
cache entries, and it opens files the compiler currently never opens. Bound it:
only for a synthesised soname (the existing provenance test), only for candidates
the cache already resolved, and only once per header. A header import is rare;
this is not on any hot path.

## Not blocked, and nothing waits on it

`import "GL/gl.h"` works today and `import "SDL2/SDL.h"` gives a compile error
that names the real problem instead of a binary that dies at exec. This makes the
next tier of headers work rather than unblocking anything.

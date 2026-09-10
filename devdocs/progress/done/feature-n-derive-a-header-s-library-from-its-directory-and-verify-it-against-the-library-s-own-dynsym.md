---
slug: feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym
track: N
prio: 50
type: feature
status: done
owner: frankH
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

## 2026-09-10 — front of the SDL chain, and the control's POPULATION is a row requirement

`366e0e8a9` cleared the inline-asm `Q`/`q` blocker and SDL2 still does not
import: `import "/usr/include/SDL2/SDL.h"` dies on `memcmp` from `libsdl.so`,
this ticket's own guard firing correctly, **before** any asm is reached. So this
is now the first thing between the fleet and a running lekkerzeilen. Wired to
[[umbrella-lekkerzeilen-compiles-and-runs-under-nilpy]] (prio 90) and to
[[task-b-write-the-lekkerzeilen-pxx-platform-backend]]; owner handed to frankH by
frankB, which holds the SDL chain's other wall.

The counterexample is now measured on both sides (frankH): `libSDL2-2.0.so.0`
exports `SDL_Init` and `SDL_CreateWindow`; **`libnet.so.9` exports ZERO of
`net/if.h`'s symbols** (`if_nametoindex` is in libc). A dynsym check accepts the
first and rejects the second, which is exactly the `does this library answer`
upgrade this ticket asks for.

**A ROW REQUIREMENT, not just a body note (frankB):** the positive control is
`net/if.h` asserted as REFUSED, and **it must be drawn from the population the
617 resolutions come from** — a header whose directory-derived library genuinely
EXISTS on the box and genuinely does not answer. `libnet.so.9` is installed
here. **On a box where it is not installed, that control passes because the
library is absent, certifying the check while testing nothing** — the
wrong-population control, in the one place this ticket cannot afford it. The
assertion must therefore establish the library's presence as a PRECONDITION and
branch on it, rather than inferring refusal from a failure of any kind.

The population question stays open and is not settled by the counterexample: 617
directory-derived resolutions is a large new surface, and dynsym is what makes
the guess safe rather than what makes it correct.

## 2026-09-10 — RESOLVED (frankH). Both halves landed; SDL2 now resolves

The directory is used as the library key and the candidate must EXPORT the
symbol before anything is accepted. `compiler/elfdynsym.inc` is a new minimal
ELF64 `.dynsym` reader; `LdCacheDirCandidate` in `pasparser_proc.inc` generates
the candidate; `RegisterExternal` in `symtab.inc` is the choke point that
decides, on the path that today is already a hard compile error.

**Measured outcomes, this box:**

| subject | before | after |
| --- | --- | --- |
| `FLAC/stream_decoder.h` | `libstream_decoder.so`, refused | **`libFLAC.so.14`**, runs |
| `net/if.h` | `libif.so`, refused | **`libc.so.6`**, and `libnet.so.9` is NOT in the binary |
| `GL/gl.h` | `libGL.so.1` | `libGL.so.1`, unchanged |
| `SDL2/SDL.h` | died on `libsdl.so` | past library resolution entirely |

`import "/usr/include/SDL2/SDL.h"` now fails at
`C: inline asm template has an unsupported instruction: bswapl`, in
SDL_endian.h — the asm chain, not the soname chain. **This ticket's wall is
gone and the next one is Track C/A's.**

### The 617 number in the body above is RETIRED, not adjusted

It was measured against `lib<key>.so.`, which is the rule the fix does NOT
implement — `libSDL2-2.0.so.0` is unreachable under it, and that is the one
library the chain was blocked on. Quoting it later would describe a rule that
is not in the tree. Re-measured over every `.h` in a `/usr/include`
subdirectory here, 7269 of them: **file stem resolves for 120, directory
resolves for 1472 more.**

### The loosening, and why it is nearly free

Allowing a `-` where the strict rule demands the `.` is what reaches
`libSDL2-2.0.so.0`. Compared as OUTCOMES per key rather than by filtering on
"newly matches" — that filter restates the hypothesis and cannot see a row that
moves:

- directories that GAIN an answer: **exactly two**, `SDL` and `SDL2`
- directories whose answer CHANGES: **zero**, so nothing that resolves today moves
- run unconditionally it would cost 46 extra candidate entries box-wide, `xcb`
  going from 1 candidate to 20, harfbuzz 1 to 5, cairo and pulse 1 to 3

So the loosened pass runs **only on a strict miss**. Every one of those
directories is answered strictly, which leaves the true added cost at two
libraries. That ordering is the design, not an optimisation.

### The re-declared-libc arm, which the ticket did not anticipate

The first symbol `import SDL2/SDL.h` asks about is **`memcmp`** — SDL_stdinc.h
re-declares it, and libSDL2 has never exported it and never should. A
per-symbol reading of "does this library answer" refuses that, and refusing it
is wrong. So the question asked is about the SYMBOL: which library on this box
DEFINES it — the header's own when it exports it, else libc or libm. That is
the same evidence standard one step wider, and it is why `net/if.h` now lands
on `libc.so.6`, which is both true and where those symbols actually live.

**This changes the counterexample's expected outcome, and for the better.** The
ticket predicted `net/if.h` REFUSED. Measured, it is ACCEPTED-as-libc, and the
assertion that carries the meaning is that the binary does **not** name
`libnet.so.9`. That is what the row asserts.

### Guards

`test/test_elfdynsym.pas`, 14 rows, all paired over one variable — same key two
paths, same symbol two libraries, same library two symbols. The reason it is a
standalone harness rather than a compiled program: of 250 multi-entry cache
keys on this box **every one lists its x86-64 entry first** (sole exception
`ld-linux.so.2`, which no header directory can name), so `ElfIsNative64` never
refuses anything reachable through the compiler's front door — while remaining
the ONLY thing separating the libSDL2 twins, which both export `SDL_Init`.

That harness caught its own instrument first: `Reset` on a typed file opens
read/write, every library it reads is root-owned, so `LoadFile` returned empty
and **every refusal row passed while every accept row failed** — a reader that
refuses everything, which is exactly the shape the pairing exists to catch.

### Open, and not closed by this

The population question stands: 1472 directory-derived resolutions is a large
new surface and dynsym makes the guess **safe**, not **correct**. A library
that exports the symbol is a library that answers; it is not proof it is the
library the author meant. No evidence of that shape has turned up yet.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

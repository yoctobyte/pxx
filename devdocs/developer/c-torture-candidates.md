# C Torture-Corpus Candidates

**Snapshot:** 2026-06-28

This note collects C libraries and applications that are useful as compiler
torture workloads. It complements `plan-c-frontend-test-ladder.md`: that plan
defines the immediate sequence; this file is the broader zoo to pull from as the
C frontend, CRTL, PAL, ABI, and optimizer mature.

These are not automatic dependencies. Stage imports under `library_candidates/`
or an equivalent test-candidate area, pin exact revisions, and classify failures
as Track A/B/C tickets instead of hiding them in candidate glue.

## Already Tracked Or Partly Covered

| Candidate | Current project hook | Why it matters |
| --- | --- | --- |
| SQLite | [[feature-c-desktop-lua-sqlite-path]], [[task-sqlite-libc-free-runtime-bringup]], `plan-c-frontend-test-ladder.md` | The flagship C frontend target: portable amalgamated C, parser, VM, B-tree, VFS, structs, callbacks, varargs, and huge upstream test surface. |
| Lua | [[feature-c-desktop-lua-sqlite-path]], `plan-c-frontend-test-ladder.md` | Compact VM/parser/GC workload. Already drove many C frontend fixes; remaining float/value-model work is documented on the active ticket. |
| musl libc | `plan-c-frontend-test-ladder.md`, [[feature-c-runtime-library]] | Clean C libc source. Best source-shape test for future CRTL re-hosting after the minimal hand-written CRTL can bootstrap real programs. |
| C regex candidates | [[feature-c-regex-library-devtest]] | Existing staged C regex dev-test path; keep regex-specific work on that ticket. |
| stb, sokol, raylib | `game-library-candidates.md` | Already listed as game/app-shaped C candidates. This file keeps their broader compiler-torture role visible too. |

## Small Baselines

| Candidate | Why it is interesting | First useful probe |
| --- | --- | --- |
| zlib | Classic small portable C. Bit manipulation, sliding windows, old-school pointer-heavy style, deterministic compression/decompression oracle. | Compile deflate/inflate core and compare known compressed fixtures. |
| miniz | Single-file zlib-ish compression. Smaller import shape than full zlib and already named in the C frontend ladder. | Compile a no-stdio/no-archive subset, compare round-trip bytes. |
| cJSON | Small heap-using JSON parser. Good structs, pointers, strings, allocation, recursion, and parser control flow. | Parse/print a tiny JSON corpus and compare output. |
| jsmn | Tiny tokenizing JSON parser with minimal allocation pressure. Good early parser workload. | Tokenize fixed JSON fixtures and compare token ranges. |
| yyjson | Highly optimized JSON library. Strong later test for performance-oriented C, SIMD/config paths, and tight memory loops. | Start with scalar configuration and small DOM/read-write tests. |
| sha256/md5/blake2/TweetNaCl | Pure integer, rotations, fixed arrays, endian conversions, and known vectors. | First-rung C codegen probes before heap, IO, or varargs. |

## Image, Audio, And Data Codecs

| Candidate | Why it is interesting | First useful probe |
| --- | --- | --- |
| libpng | Real-world C with structs, callbacks, zlib dependency, endian handling, chunk parsing, and error paths. | Compile after zlib/miniz; decode a tiny PNG and compare bytes/checksum. |
| libjpeg-turbo / jpeg6b-style code | Pointer-heavy, macro-heavy image codec where numeric correctness matters. | Prefer scalar/no-SIMD configuration first; decode a tiny fixture. |
| stb_image | Single-header image decoder with broad format coverage and preprocessor-heavy style. | Avoid as first probe if `setjmp` is still missing; begin with formats/configs that avoid it. |
| stb_truetype | Font parsing/rasterization, fixed-point/math-heavy code, single-header import style. | Parse a minimal TTF and compare simple metrics or raster checksum. |
| stb_vorbis | Single-file audio codec. Good bitstream, float, table, and decode-loop stress. | Later than integer-only codecs; compare a short decoded PCM checksum. |

## VMs, Languages, And Compiler-Like Workloads

| Candidate | Why it is interesting | First useful probe |
| --- | --- | --- |
| Wren | Small scripting language VM in C. Object model, bytecode VM, parser, GC, and portable build surface. | Compile the core VM and run a tiny script suite. |
| Duktape | JavaScript engine in C. VM, GC, parser, portability, and self-contained build shape. | Start with default single-source build and a small JS eval suite. |
| QuickJS | Serious compact JS engine. Parser, VM, GC, bigint, modules, Unicode, atom tables, and heavy runtime semantics. | Later than Duktape/Wren; run a tiny interpreter smoke before full tests. |
| TinyCC / chibicc / lacc | C compilers written in C. Very meta: lexing, parsing, symbol tables, codegen, and host assumptions. | Prefer chibicc/lacc before TinyCC if GNU/asm paths get noisy; compile parser-only or tiny executable smoke first. |
| QBE | Compiler backend in C. Nice IR parser, allocator, and codegen-oriented workload. | Compile the frontend/parser/IR pieces first; backend output can be a later oracle. |

## Crypto, TLS, And Constant-Time Code

| Candidate | Why it is interesting | First useful probe |
| --- | --- | --- |
| mbedTLS | Crypto/TLS in portable C. Integer correctness, byte arrays, protocol state machines, macros, optional features. | Compile hash/block-cipher modules first, then TLS handshake pieces later. |
| BearSSL | Compact TLS/crypto with disciplined C and interesting constant-time integer code. | Start with hashes/ciphers and known vectors; defer full TLS integration. |
| libsodium | High-quality crypto library, broader platform and optimization surface. | Force portable scalar build first; compare known vectors. |

## Networking And System Libraries

| Candidate | Why it is interesting | First useful probe |
| --- | --- | --- |
| curl / libcurl | Real-world networking, callbacks, TLS backends, URL/protocol parsing, config matrix. | Dependency-heavy; start with URL/parser or tool-free library subset. |
| SDL | Portability monster: platform conditionals, system APIs, event/input/audio/video backends, build complexity. | Treat as later PAL/CRTL stress, not early C frontend proof. |
| Redis | Large C server app: data structures, networking, event loop, persistence, scripting hooks, platform assumptions. | Compile data-structure modules first; full server run comes much later. |
| nginx | Big event-driven C with modules, allocator patterns, platform conditionals, and networking. | Late-stage app target after sockets/event/PAL and configure assumptions are under control. |
| Git | Very large real software corpus, excellent portability and data-structure test. | Not an early target; build system and platform surface are the real first walls. |

## Late-Stage Boss Targets

| Candidate | Why it is useful | Why late |
| --- | --- | --- |
| FFmpeg | Massive codec and media framework: C plus assembly, configure scripts, intrinsics, macros, codecs, and platform assumptions. | Use only after scalar C, build configuration, CRTL, and optional asm/intrinsic policy are strong. |
| Full SDL/curl/nginx/Git application builds | Real software proof instead of isolated library proof. | They combine many independent walls; pull module slices first. |

## Suggested Ladder Beyond The Existing Plan

The immediate ladder remains in `plan-c-frontend-test-ladder.md`:
integer hashes -> cJSON/miniz -> SQLite -> Lua -> optional musl re-host.

After that, a useful expansion order is:

1. **More small deterministic libraries:** zlib, jsmn, yyjson scalar path.
2. **Codecs with byte or checksum oracles:** libpng, jpeg scalar path,
   stb_truetype.
3. **VMs and language tools:** Wren, Duktape, chibicc/lacc, QBE, QuickJS.
4. **Crypto/TLS:** mbedTLS modules, BearSSL, libsodium portable build.
5. **Large apps/system libraries:** curl, SDL, Redis, nginx, Git.
6. **Monster media corpus:** FFmpeg.

Keep the early landscape narrow. If a candidate introduces build-system,
platform, varargs, setjmp, threads, dynamic loading, SIMD, and floating-point
issues all at once, slice it until the first failure is attributable.

## Import Discipline

- Check license and upstream status at import time.
- Pin the upstream revision/tag and record import date, license, selected config,
  local edits, and first failing probe.
- Prefer deterministic oracles: official vectors, round-trip bytes, checksums,
  stdout equality, or upstream test subsets.
- Prefer scalar/portable configurations first. Add SIMD, assembly, threads,
  dynamic loading, and platform backends only when the baseline is meaningful.
- Split C parser/frontend/preprocessor failures to Track C; ABI/codegen defects
  to Track A; CRTL/PAL/header/runtime gaps to Track B/C depending on ownership.

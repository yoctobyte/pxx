# Game Library Candidates For Compiler Testing

**Snapshot:** 2026-06-28

This note turns the "Pascal/C game engines" discussion into a candidate list for
library-suite discovery. These are not planned dependencies. The intent is to
pull selected upstreams into `library_candidates/`, compile the smallest useful
slice, and use the failures as high-signal compiler and RTL work. For non-game C
library and application candidates, see `c-torture-candidates.md`.

## Selection Rules

- Prefer source we can compile directly, not only language bindings.
- Prefer permissive licenses for vendored candidates; GPL projects are still
  useful as local discovery workloads, but not as future bundled libraries.
- Prefer small, modular slices before full engines.
- Keep upstream source drop-in where possible. Local edits are allowed only when
  recorded with the reason.
- File real gaps back as Track A/B/C tickets instead of hiding them in candidate
  glue.

## Best First Pascal Candidates

| Candidate | Upstream | Why it is useful | First probe |
| --- | --- | --- | --- |
| Castle Game Engine | https://github.com/castle-engine/castle-engine | Active modern Object Pascal engine, FPC/Lazarus and Delphi oriented, broad coverage: classes, generics, RTTI/streaming-style patterns, resources, math, assets, platform abstractions. Good flagship Pascal compatibility target. | Compile a leaf utility/math unit and one minimal non-editor example before touching the full editor/build-tool surface. |
| Apus Game Engine | https://github.com/Cooler2/ApusGameEngine | Open-source Delphi/Pascal game engine used in real shipped games. Likely a different Delphi/FPC dialect shape than Castle, with 2D engine, GUI, scripting, and cross-platform utility code. | Compile core `Apus.*` utility and engine type units, then a tiny example from `ApusEngineExamples`. |
| New-ZenGL | https://github.com/Seenkao/New-ZenGL and https://sourceforge.net/projects/new-zengl/ | Smaller Pascal 2D/OpenGL library, Lazarus/FreePascal and Delphi oriented. GitHub was last pushed in 2023; SourceForge shows a 2026 update, so check both before pinning a snapshot. | Compile non-window utility modules first; then a headless or stubbed graphics smoke. |

## Pascal Candidates To Defer

| Candidate | Why defer |
| --- | --- |
| Andorra 2D | Old DirectX/OpenGL plugin-era Delphi/Lazarus project. Useful only if we want legacy Delphi syntax stress. |
| Quad Engine | Older Windows/DirectX-shaped Delphi 2D engine. Likely poor return until Windows/DirectX-style assumptions matter. |
| Asphyre/PXL/Afterwarp family | More graphics framework than current engine. Keep as historical Delphi-game-dev coverage after the active/smaller targets above. |
| Pascal wrappers for raylib, Allegro, SDL, Irrlicht | Not first-class candidates for source-compilation testing because the engine/library source is C or C++. They may become Pascal binding tests later, but they do not test Pascal-native engine implementation. |

## Best First C Candidates

| Candidate | Upstream | Why it is useful | First probe |
| --- | --- | --- | --- |
| stb | https://github.com/nothings/stb | Single-file C libraries, permissive public-domain/MIT choice, minimal build machinery. Excellent first C-source frontend workload. | `stb_image` header/import smoke, then one implementation translation unit with tiny PNG/JPEG-disabled fixtures where needed. |
| cglm | https://github.com/recp/cglm | C graphics math, header-only/allocation-free API surface, strong struct/vector/macro pressure without OS/window dependencies. | Compile scalar-only headers first; defer SIMD-specific paths until attributes/intrinsics are ready. |
| miniaudio | https://github.com/mackron/miniaudio | Single-file C audio library with no dependencies except the standard library. Good C preprocessor, structs, callbacks, enums, and backend-selection stress. | Compile null/custom backend configuration before ALSA/Pulse/etc. |
| ENet | https://github.com/lsalzman/enet | Small MIT reliable-UDP networking library, almost all C, exercises sockets, structs, packet queues, and byte-order code. | Header import plus `packet.c`/`protocol.c`; defer `unix.c` until PAL/socket CRTL coverage is ready. |
| Nuklear | https://github.com/Immediate-Mode-UI/Nuklear | Single-header ANSI C immediate-mode GUI, public-domain/MIT. Good struct-heavy, enum-heavy, macro-heavy workload without owning window/render backends. | Compile `nuklear.h` with `NK_IMPLEMENTATION` and no optional font/backend extras. |
| sokol | https://github.com/floooh/sokol | Standalone C headers for app/gfx/audio/time/fetch; current, small-file import style, good for app/runtime abstractions. | Start with `sokol_time.h` and maybe `sokol_args.h`; defer `sokol_app.h` and graphics backends. |
| raylib | https://github.com/raysan5/raylib | Plain C99 game framework with many examples and no external dependencies in normal use. Strong future demo target. | After stb/cglm: header import, then a headless/rlgl-free subset or one non-window utility module. |
| Orx | https://github.com/orx/orx | Real data-driven 2D C engine, zlib license, modular/plugins architecture. Good "actual engine" target after smaller C libraries. | Probe core config/resource/object code, not the whole platform plugin set. |

## Larger Or Later C Targets

| Candidate | Why later |
| --- | --- |
| SDL | Excellent C multimedia foundation, but large and platform-backend heavy. It is better as a later CRTL/PAL stress test than as an early source-frontend target. |
| Allegro 5 | Useful C game/multimedia library, but CMake/addon/platform dependency surface is larger than the first-wave candidates. |
| TIC-80 | Mostly C fantasy computer with many embedded languages and build options. Valuable as an end-to-end app once C frontend and CRTL are much stronger. |
| Chocolate Doom | Very C-shaped source port and good retro engine reference, but GPL-2.0 and SDL-backed; use only as local discovery/benchmark unless licensing policy changes. |
| ioquake3 | C/GPL-2.0 baseline engine with SDL/OpenAL and dynamic renderer/game-library assumptions. Valuable later for shared-library, VM/QVM, renderer, and networking pressure. |
| Build/EDuke32 family | Useful old-school engine lineage, but codebase/build/platform assumptions are not first-wave material. |

## First-Wave Recommendation

Start with two tracks:

1. **Pascal real-world compatibility:** New-ZenGL, then Apus, then Castle. This
   sequence grows from smaller library to real engine to large flagship.
2. **C source-frontend ladder:** stb, cglm, miniaudio, ENet, Nuklear, sokol,
   raylib, Orx. This sequence deliberately moves from single-file/header-heavy
   C toward real engine/platform code.

Use `library_candidates/` for all imports. Once a candidate compiles and has a
small owned smoke, decide whether it remains a discovery workload or graduates
to `lib/`, `lib/crtl/`, or examples.

## Source Notes

- Castle advertises a modern Pascal, cross-platform 2D/3D engine with a visual
  editor and showed 2026 news on 2026-06-28:
  https://castle-engine.io/
- Apus GitHub describes an open-source Delphi/Pascal game engine under BSD-3:
  https://github.com/Cooler2/ApusGameEngine
- New-ZenGL SourceForge describes a Pascal cross-platform 2D/OpenGL/OpenGL ES
  engine and shows a 2026-03-03 update:
  https://sourceforge.net/projects/new-zengl/
- raylib upstream describes plain C99 with included dependencies and v6.0 in
  2026:
  https://github.com/raysan5/raylib
- Orx upstream describes a zlib-licensed, heavily data-driven 2D game engine:
  https://github.com/orx/orx
- SDL, Allegro, sokol, stb, miniaudio, cglm, Nuklear, ENet, TIC-80,
  Chocolate Doom, and ioquake3 source/language/license notes come from their
  upstream repositories linked above.

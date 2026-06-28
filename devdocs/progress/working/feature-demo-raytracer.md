# Demo — CPU ray tracer

- **Type:** feature
- **Track:** B
- **Status:** working
- **Owner:** agent
- **Opened:** 2026-06-22
- **Relation:** Visual compute demo. May use `lib/rtl/math.pas`, but should keep
  a small no-transcendental path possible where practical.

## Goal

Build a small CPU ray tracer under `examples/raytracer/`, without OpenGL. The
first version should render into an image/bitmap buffer and display through the
existing PCL/custom drawing or terminal/image-rendering stack, with an optional
headless render mode for deterministic tests.

## Scope

- Scene with spheres and planes, camera, point/directional light, and shadows.
- Materials with diffuse color and simple specular/reflection terms.
- No OpenGL/GPU dependency; all rays are computed on the CPU.
- Render to an image buffer; optionally save PNG once the PNG path is convenient.
- Interactive controls if hosted GUI is used: camera orbit/pan/zoom, quality
  toggle, restart render, and resize-aware rerender.
- Deterministic seeded scene or fixed default scene for tests.

## Math-library note

A clean ray tracer naturally wants vector normalization, square root, dot
products, and possibly trig for camera controls. That may depend on `math.pas`
or runtime float support. Keep the core structured so a simpler profile can
avoid extra math where useful:

- squared-distance comparisons where exact length is unnecessary;
- precomputed camera basis for deterministic tests;
- optional fixed-point or approximate math experiments later.

Do not distort the source just to avoid `math.pas`; file missing math/runtime
gaps separately if the platonic implementation needs them.

## Coverage

- Records/classes for vectors, rays, materials, lights, and hittable objects.
- Floating-point arithmetic in nested loops.
- Dynamic arrays for scene objects and render buffers.
- Recursion or bounded iteration for reflections.
- Custom drawing / image output path without OpenGL.
- Keyboard/mouse/resize behavior if implemented as a PCL application.

## Acceptance

- `examples/raytracer/` contains a deterministic CPU-rendered scene.
- It compiles with `$(PXX_STABLE)` and does not require OpenGL.
- A smoke test renders a small resolution and validates a stable image hash or
  selected golden pixels.
- Hosted interactive mode, if present, handles resize and basic keyboard/mouse
  controls without corrupting render state.
- Any compiler, math-library, or widget-set gaps found during implementation are
  filed as separate tickets.

## Log

- 2026-06-22 — Opened on user request: no-OpenGL ray tracer application, with
  optional math-library dependency and room for simpler math profiles where
  practical.
- 2026-06-25 — **Landed (Track B):** headless CPU ray tracer at
  `examples/raytracer/raytracer.pas`. Fixed deterministic scene (3 spheres on a
  checkerboard plane, point light), ambient + Lambert diffuse + Blinn specular,
  hard shadows, up to 3 mirror-reflection bounces, sky gradient. `Vec3`/`TSphere`
  records, dynamic-array scene, recursion for reflections, `math.pas` Sqrt/Power.
  Modes: no-arg = deterministic SMOKE_W×SMOKE_H render + integer pixel CHECKSUM
  (EXPECTED=297935246), `--ppm FILE [W H]` = colour PPM (P3). Wired into
  `make lib-test` (gate, ALL OK) + `make demos`. Cross-target: checksum identical
  on x86-64 and aarch64 (transcendental Power is deterministic via math.pas).
  Gaps found while keeping the source platonic:
  - [[bug-plain-byvalue-record-param-temp]] — plain by-value record param >8B
    rejects a temp arg (only `const` was fixed). Used `const` vector params
    (idiomatic anyway) to compose; ticket tracks the bare form.
  - [[feature-arm32-large-aggregate-result]] — arm32 can't return a 24-byte
    `Vec3` (sret for >4-word aggregate results). i386 still lacks float params.
    So the cross gate stays mandelbrot-only.
  **Still open:** interactive hosted mode (camera orbit/zoom, resize), optional
  simpler-math profile.
- 2026-06-25 — **PNG output added.** `--png FILE [W H]` builds a `TImage` and
  writes a real PNG via the `png`/`zlib` RTL (`PngEncodeRGBA` + raw `PalWrite` of
  the byte stream through the `Text` handle). Verified: `file` reports a valid
  RGBA PNG and it round-trips losslessly (encode checksum == decode checksum).
  `--ppm` retained; render now goes through a shared `TImage`, smoke checksum
  unchanged (297935246). Host + aarch64 build clean; arm32 still blocked on
  [[feature-arm32-large-aggregate-result]] (Vec3 result). New gap found:
  [[bug-aarch64-arm32-record-temp-byvalue-arg]] — `ImageSetPixel(img,x,y,
  MakeRGBA(...))` (record temp arg) fails aarch64/arm32 codegen; fixed by a named
  `TRGBA` local (idiomatic). (mandelbrot deliberately kept PPM-only: it is in the
  Track A float-determinism cross gate and pulling png/image/zlib would break its
  aarch64/arm32 cross-build.)

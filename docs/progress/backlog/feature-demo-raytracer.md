# Demo — CPU ray tracer

- **Type:** feature
- **Track:** B
- **Status:** backlog
- **Owner:** —
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

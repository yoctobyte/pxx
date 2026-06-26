# PCL OpenGL GLArea demo

- **Type:** feature
- **Track:** B
- **Status:** done
- **Owner:** — (lock released; last worked by Codex)
- **Opened:** 2026-06-21
- **Relation:** Demo/library request for richer PCL GUI examples.

## Goal

Add a small GtkGLArea-backed OpenGL surface to PCL and a rotating triangle demo
under `examples/gl/`, proving that PCL can host GL drawing alongside ordinary
forms, labels, and timers.

## Scope

- `lib/pcl/gl_c.h`: minimal GtkGLArea/OpenGL declarations.
- `lib/pcl/glarea.pas`: `TGLArea` control with render/resize trampolines and
  `QueueRender`.
- `examples/gl/triangle.pas`: animated OpenGL triangle demo.

## Acceptance

- Demo source is present and idiomatic enough to compile once the compiler/PCL
  surface is stable enough for this feature class.
- Any remaining compiler gaps discovered later get separate Track A tickets.

## Log
- 2026-06-21 — Found untracked WIP in `lib/pcl/gl_c.h`,
  `lib/pcl/glarea.pas`, and `examples/gl/triangle.pas` with no matching ticket;
  captured it as a working ticket instead of leaving it implicit in the dirty
  tree.

- 2026-06-21 — HALTED → `unfinished/`. `working/` lock released (no active agent). TGLArea + triangle demo committed as 95a3d9c (lib/pcl/glarea.pas, gl_c.h, examples/gl/).
- 2026-06-22 — DONE in this commit. Fixed the triangle demo's local variable
  name so pinned v32 resolves the `TGLArea` instance correctly, and added
  `examples/gl/triangle.pas` to the `make demos` dashboard. Verified direct
  compile with `stable_linux_amd64/default/pinned -Fulib/pcl
  examples/gl/triangle.pas /tmp/demo_triangle`; existing `make gui-test` is
  green.

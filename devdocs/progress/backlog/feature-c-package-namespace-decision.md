---
prio: 40
---

# Decide the Pascal-import namespace for C packages (`uses zlib` collision)

- **Type:** decision + small feature (compiler `uses` resolution + `lib/clib`
  layout). Track C (frontend surface) — **needs a user decision first**.
- **Split 2026-07-08** out of [[feature-c-runtime-library]] when that umbrella
  resolved (crtl substrate + autopull long since live; this was its one open
  design question, deliberately deferred there since 2026-06-20).

## Problem (unchanged from the umbrella)
Direct Pascal import of C packages is wanted; Pascal wrappers stay optional.
- `uses zlib` as a Pascal wrapper vs. `uses zlib` as a direct C package
  collide.
- `uses c/zlib` is clear but not Pascal-compatible syntax.
- `uses zlib.h`-shaped imports bind the language surface to filenames.

Also still open: the `lib/clib/<package>/` layout (metadata, include/, src/)
has no instance yet — zlib/sqlite/tcc/cjson all live in gitignored
`library_candidates/` as corpus, not as importable packages.

## Ask
User picks the namespace shape; then implement resolution in the frontend and
promote the first real package (zlib is the natural candidate — it already
builds byte-identical to gcc) into `lib/clib/` as the reference layout.

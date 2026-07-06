---
prio: 25  # auto
---

# Real-world C programs as compiler stress tests (brainstorm)

- **Type:** idea / test-coverage backlog — Track C+B (C frontend + crtl)
- **Status:** backlog (not scheduled — user prefers moving elsewhere next, e.g.
  the Nil-Python frontend). Captured because real-world C programs have proven
  invaluable: lua 5.4 and sqlite3 each surfaced a dozen+ genuine codegen / ABI /
  crtl bugs that no synthetic test caught (see [[feature-c-cross-lua-sqlite]]).
- **Opened:** 2026-07-05

## Why these matter

Big real C programs are the best bug-finders we have. They exercise the C
frontend, the crtl syscall/string layer, and the cross-target ABIs under real
load. lua + sqlite already run on x86-64/aarch64 (and printf/variadic now work on
i386/arm32). Each new program is a fresh discovery→ticket loop. Bonus of C
programs specifically: they test the C compiler WITHOUT leaning on our
Object-Pascal RTL, so they dodge the FPC-compat RTL / RTTI / library-landmine
class of bugs entirely.

## Candidates (rated realism × signal)

- **busybox — 🟢 top pick, applet-at-a-time.** Standalone C, no external deps,
  brutally syscall-heavy → hammers crtl exactly where it is thin. Don't build the
  whole multi-call binary (obscure headers + CONFIG_* maze); build ONE applet:
  `true`/`echo`/`cat`/`yes` are dozens of lines. Green `busybox cat` = real
  trophy + fast feedback. Same loop as lua/sqlite.
- **tcc (Tiny C Compiler) — 🔥 the flex / meta test.** A C compiler, in C, famous
  for compiling itself. Our C frontend builds tcc → tcc builds hello-world = a
  mic-drop statement about the C frontend's completeness. ~50k lines, mostly
  self-contained.
- **p2c — Pascal→C translator, in C (~30k lines).** Literally "a Pascal compiler
  in C" — the buildable stand-in for the gpc idea below.
- **stb / cJSON / miniz — 🟢 palate cleansers.** Single-header C libs, tiny,
  clean, no syscall jungle. Fast confidence hits; good for shaking out frontend
  corners quickly.
- **micropython — Python interpreter in C.** Compiled by our C frontend, then it
  runs Python — while we ALSO have a Nil-Python frontend. Two roads to Python,
  one compiler. Ambitious.
- **DOOM — 🎮 the eternal "but does it run DOOM."** Source is C; needs a
  framebuffer / ASCII / headless render shim, but headless perft-style ports
  exist. Pure clout, one funny thing. Low signal, high morale.

## North star (no ceiling)

- **Compile GCC itself.** The ultimate real-world C test — there is no ceiling
  for this project. Not near-term (GCC is enormous, GMP/MPFR/MPC deps, decades of
  autoconf), but it is the honest end of the curve, and worth writing down as the
  aspiration.

## gpc note (why it is NOT on the buildable list)

GNU Pascal was raised as a target: a Pascal compiler written in C would test our
C frontend and sidestep FPC's RTL/RTTI landmines. Sound reasoning — but gpc is a
GCC *front-end*, welded to GCC's backend/internals, not a standalone program you
can compile alone. Use **p2c** or **tcc** for the same spirit.

## Suggested order (signal per effort, when picked up)

1. busybox `cat` (crtl stress — our actually-thin layer)
2. tcc (frontend-completeness flex)
3. cJSON / stb (quick corner-shaking)
4. DOOM (morale)

## Related

- [[feature-c-cross-lua-sqlite]] — the proven pattern; open cross bugs it left
  (riscv32 softfloat %f, arm32/i386 lua/sqlite garbage-output codegen bugs,
  typedef-array-param→pointer decay) are the current C-frontend loose ends.

---
slug: feature-c-pragma-once
track: C
prio: 70
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libxkbcommon 1.13.1 through compdb.py replay)
tags: [cpreproc]
summary: "pxx had no #pragma once: a header guarded only by it was spliced once per #include. libxkbcommon's utils.h (via test.h and keymap.h) defined its static inline functions twice. Now the file that says `#pragma once` is recorded by its normalised path (`.`, `..`, `//` folded; the real path, not one changed by #line), and a later #include that resolves to it is skipped. The list is reset per unit. Symlinks are not resolved (gcc compares files), so two spellings through a symlink still include twice. Test: c_xkbpp26 includes test/c_xkb_preproc_inc/once.h by three spellings; a second splice reaches its #error."
---

# C pragma once

CPNormPath / CPOnceSeen / CPOnceMark in cpreproc.inc, CPPragma's `once` arm, and the skip in
CPInclude right after the search resolves CPrepPath.

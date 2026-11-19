---
slug: bug-a-the-bare-esp-crtl-refusal-moved-to-a-pxx-bridge-symbol-and-lost-its-profile
track: A
prio: 30
type: bug
status: done
created: 2026-11-19
owner: claude-dupwt
found-by: claude-dupwt (red test-emit-obj row); bisected by pxx2 to 8e478eab32
tags: [esp, bare, diagnostics, test]
blocked-by: []
summary: "On --esp-profile=bare, C that reaches crtl (test/c_reaches_crtl_on_the_esp_idf_profile.c) must be refused, and the message must name the profile and must not read as an internal fault. Since 8e478eab32 (aggregates zeroed and copied inline when there is no RTL) the refusal came later, at the first crtl bridge call: `__pxx_open is a pxx-internal runtime symbol and cannot be imported dynamically ... a missing uses ...`. That names no profile, gives advice that is wrong for a deliberate exclusion, and failed the c_crtl_bare rows. A `__pxx_*` refusal on a build that excludes the RTL (NoDefaultRtl or TargetIsEspClass, the FindHeapHelperOrRefuse condition) now says what the PXXMemZero refusal said: the bare profile excludes the runtime, so build for ESP-IDF or stay freestanding. The row's symbol grep accepts either symbol."
---

# The bare-ESP crtl refusal moved to a __pxx_ bridge symbol and lost its profile

## Before / after (xtensa --esp-profile=bare --emit-obj c_reaches_crtl_on_the_esp_idf_profile.c)

- before: `__pxx_open is a pxx-internal runtime symbol and cannot be imported
  dynamically: ... a missing `uses` of the unit that defines it, or a C
  translation unit compiled without its Pascal bridge.` The row's two greps
  for PXXMemZero and esp-profile=bare both failed.
- after: `__pxx_open is part of pxx's runtime bridge, and this build excludes
  the default RTL ... --esp-profile=bare ... Either build it for the ESP-IDF
  profile ... or keep the unit freestanding ...`

The refusal itself is still the contract: bare stays freestanding, and the
freestanding bare row (c_freestanding_on_bare_esp_needs_no_rtl.c) still builds.

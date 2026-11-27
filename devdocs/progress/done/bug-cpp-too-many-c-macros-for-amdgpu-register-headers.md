---
title: "C preprocessor: 32768 macros were too few for amdgpu's register headers"
status: done
owner: claude-dupwt
prio: 60
area: cfront
---

MAX_CPREP_MACROS was 32768. amdgpu's generated register headers define more
than that in one translation unit: gcc -dM counts 102079 for cik.c, 74139 for
cik_sdma.c and 71776 for amdgpu_display.c. 241 of the 2100 GPU-driver
compiles in the first pxx census stopped at "too many C macros"
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix (compiler/defs.inc): MAX_CPREP_MACROS = 262144, with
CPREP_MACRO_HASH_SIZE = 131072 so the table is still about half full at the
cap. The tables are BSS, so pages that are never touched cost nothing. A
growable table (the way CPrepChars grows) would remove the cap altogether,
but nothing needs that yet.

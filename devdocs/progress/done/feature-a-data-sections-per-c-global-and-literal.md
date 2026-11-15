---
slug: feature-a-data-sections-per-c-global-and-literal
track: A
prio: 60
type: feature
status: done
created: 2026-11-15
found-by: claude-opus (toybox size)
tags: [emit-obj, link, object-model, size]
blocked-by: []
summary: "The data half of --function-sections (gcc's -fdata-sections) for x86-64 objects, plus baked C initialisers by default for such objects. Each C global the object defines gets .data.<name>/.bss.<name>, each interned string .data.pxx.str<n>; every section-relative data reference (code, .rela.data, C initialisers, symbols) is rebased to its cut (elfwriter.inc ObjPlanDataCuts/ObjDRef). Bytes between globals ride with the global before them. Refused for .data if a self-relative RTTI word would span two cuts; literal cuts skipped near SHN_LORESERVE. --emit-obj --function-sections on x86-64 now implies --c-static-data (--no-c-static-data opts out): the init-thunk stores had made every crtl global and literal reachable from .init_array. pxx --link accepts several .data/.bss per object. toybox 0.8.15 default objects: 9.47 MB -> 1.69 MB (.text 5.35 -> 1.33, .data 4.06 -> 0.31, .bss 16.8 -> 0.15 MB); --shared-runtime 3.76 -> 1.71 MB. gcc: 0.48 MB."
---

# Data sections per C global and literal

Pieces:

- elfwriter.inc: ObjPlanDataCuts, ObjDRef, ObjGroupDataRelocs,
  ObjNumberDataCuts; writeELFRelX64General collects `.rela.data` before
  writing it.
- elfreader.inc: `.data.*`/`.bss.*` are DATA/BSS, and an object may have
  several.
- compiler.pas: the CStaticDataMode default and `--no-c-static-data`.

Measured along the way, toybox default objects:

| step | binary |
|---|---|
| cuts only | 9.47 MB (.bss 16.8 -> 2.3 MB) |
| + baked initialisers | 5.12 MB |
| + literal cuts | 1.69 MB |

The literal cuts were the big one: every object's 17.6 KB literal pool rode
with `pxx_slash` and was kept by any live function using a literal.

Test: c_redeclared_array_bakes (executable, gcc --gc-sections, pxx --link),
c_srt_dgc (default objects, gcc --gc-sections), and the c_srt rows.

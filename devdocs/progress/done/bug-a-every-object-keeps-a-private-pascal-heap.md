---
slug: bug-a-every-object-keeps-a-private-pascal-heap
track: A
prio: 60
type: bug
status: done
created: 2026-11-14
found-by: claude-opus (toybox size)
tags: [emit-obj, link, object-model]
blocked-by: []
summary: "Option B of decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit, now the default. The Pascal runtime every hosted --emit-obj object carries (units builtinheap, platform, platform_backend, pxxcio: PXXAlloc, strings, interfaces, PAL wrappers) was emitted LOCAL, so each object had its own copy of ~14 KB of helpers that no linker may fold (toybox: 205 x, 2.9 MB) AND its own heap state: Pascal-level memory allocated through one object's PXXAlloc and released through another's went to a different allocator. crtl had been made WEAK for exactly this reason (ObjProcBind); the Pascal runtime never got the same treatment. Now exported WEAK on hosted x86-64/aarch64 objects (ObjProcIsBuiltinRtl), so the linker keeps one copy and every caller reaches one heap; each unit's own __init_/__fini_ stays local. They are not DCE roots (only what the object reaches is emitted). ESP objects are unchanged (ObjRuntimeIsPrivate). Verified linked by pxx --link and by gcc."
---

# Every object kept a private Pascal heap

elfwriter.inc ObjProcIsBuiltinRtl, used by ObjProcIsExported and ObjProcBind;
dce.inc's export-root loop skips those procs.

Measured on toybox 0.8.15 with --shared-runtime: binary .text 5.97 MB -> 3.04 MB.

Test: test/c_shared_runtime_{main,part}.c, rows c_srt_d (pxx --link) and
c_srt_dg (gcc), default self-contained objects.

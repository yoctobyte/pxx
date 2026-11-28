---
slug: bug-ir-a-call-takes-at-most-128-arguments
track: core
prio: 30
type: bug
status: backlog
owner: unassigned
created: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libxkbcommon 1.13.1 through compdb.py replay)
tags: [ir_codegen, limits]
summary: "MAX_CALL_ARGS = 128 caps a call's arguments ('C call: too many arguments'). gcc has no such limit. libxkbcommon's tests call the variadic test_key_seq with up to 353 (modifiers.c 353, keyseq.c 298, keymap.c 258), so those 3 test programs of xkbcommon's 190 non-library units fail. The library is 75/75. Raising the constant is not the fix: IREmitNode, the recursive expression emitter, holds ten fixed [0..127] arrays (argNodeArr, slotArg, slotIsSse, ...) in every frame, so a bigger bound grows every recursion level. Move the call lowering's arrays out of IREmitNode's frame (a heap buffer per call, or a separate procedure), then lift the bound."
---

# Ir a call takes at most 128 arguments

Found by pxx2 while replaying libxkbcommon. Not started.

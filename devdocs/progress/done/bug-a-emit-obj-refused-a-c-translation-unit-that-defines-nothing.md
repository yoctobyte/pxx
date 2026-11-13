---
track: A
tags: [c, emit-obj, dropbear]
prio: 40
type: bug
blocked-by: []
summary: "--emit-obj refused any object that exports no symbol. That is right for Pascal (a unit missing cdecl/cvar/public) and wrong for C, where a TU that preprocesses to nothing is ordinary and gcc emits an empty object. libtomcrypt's error_to_string.c and dropbear's progressmeter.c are such TUs. C units are now exempt."
status: done
owner: claude
---

# --emit-obj refused an empty C translation unit

Found building dropbear 2026.94 ([[feature-c-dropbear-builds-with-pxx]]).
Libraries switch whole files off with the preprocessor: with dropbear's
configuration, libtomcrypt's src/misc/error_to_string.c and dropbear's
src/progressmeter.c have every definition inside a disabled #if. gcc
compiles them to an object with no symbols. pxx stopped with "this object
would define no linkable symbol, so nothing could ever link against it".

The refusal (compiler/elfwriter.inc) was written for Pascal, where an object
that exports nothing means a unit forgot to mark what it is for. It now
applies only when the source is not C (`not IsCFrontend`). The resulting
object links: a probe `main` linked with `pascal26 --link` next to an empty
TU's object returns its exit code.

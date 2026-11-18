---
track: A
tags: [link, shared-runtime, cache, crtl]
prio: 70
type: bug
blocked-by: []
summary: "--link's shared runtime was cached under a hash of the compiler binary alone. After an edit to lib/crtl, objects compiled against the new headers linked against the runtime built before the edit: \"undefined reference to 'wcschr'\" although crtl defines it. Nothing said the runtime was stale."
status: done
owner: pxx2
---

# The shared-runtime cache ignored crtl edits

elfreader.inc ElfRtHashCrtl: the cache key also covers a hash of crtl's
include/ and src/ trees. That hash is FNV-1a over each file's relative path
and bytes, walked in sorted name order. The crtl root is found the way the
include search finds it: PXX_HOME, then pxx.cfg's home, then next to the
binary.

Checked by hand: an edit to lib/crtl/src/dlfcn.c gave a new key and the
runtime was rebuilt (rt-<self>-<crtl>-<marker>.o).

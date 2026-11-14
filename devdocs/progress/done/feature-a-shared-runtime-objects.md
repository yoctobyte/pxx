---
slug: feature-a-shared-runtime-objects
track: A
prio: 60
type: feature
status: done
created: 2026-11-14
found-by: claude-opus (toybox size), decided by the owner
tags: [emit-obj, link, crtl, object-model]
blocked-by: []
summary: "Option A of decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit, as an opt-in. `--emit-obj --shared-runtime` leaves crtl's implementations out of the object: crtl headers only declare, crtl-owned state (stdout, errno, environ, optind, ...) becomes an undefined reference, and the TU's init thunk no longer fills environ. Every such object references `__pxxrt_needed_<target>[_ts]` (forced-in pxx/shared_runtime.h). `pascal26 --link` adds the runtime itself when that marker is referenced and undefined: it builds lib/crtl/include/pxx/runtime_all.h (every crtl header with an impl) with the same binary run as a child, once per compiler binary hash and variant, into $XDG_CACHE_HOME/pxx (or ~/.cache/pxx), renamed into place so parallel links are safe. gcc/ld without the runtime fail naming the marker. stdarg and setjmp stay in the object (compiler support, like libgcc). Measured on toybox 0.8.15 defconfig, x86-64, with B (weak Pascal runtime, sibling ticket): objects 162 MB -> 15 MB, binary 12.4 MB -> 3.76 MB; false.c compile 6.2 s -> 2.3 s CPU on a loaded box."
---

# Shared-runtime objects (option A, opt-in)

Owner decision 2026-11-14: B (self-contained, mergeable) stays the default; A
is a flag for project builds. Autodetection happens at link time, not compile
time: a compile cannot know who will link the object.

## Pieces

- `--shared-runtime` (compiler.pas): sets SharedRuntime and force-includes
  `pxx/shared_runtime.h`.
- cpreproc.inc CPAutoPullCrtlImpl: no crtl impl pulled, except stdarg and setjmp.
- cpreproc.inc predefines `__PXXRT_MARKER` (and `__PXXRT_THREADSAFE` under
  `--threadsafe`) for every C `--emit-obj`.
- cparser.inc CNeedsEnvironInit: false under --shared-runtime (the runtime's
  own thunk fills environ).
- elfwriter.inc ObjDataIsImport: a runtime-owned extern is an import under
  --shared-runtime (it was a private slot: a second, NULL stdout).
- elfreader.inc ElfLnkAddSharedRuntime / ElfRtProvide: detect, build or reuse,
  add. Variants: target x threadsafe; mixing both in one link is refused.
- lib/crtl/include/pxx/runtime_all.h: the list. A new crtl src/<name>.c needs
  its header here (pthread only under __PXXRT_THREADSAFE).
- Tools: dropbear_pxx.py uses it on x86-64 (`--self-contained` opts out;
  `--pinned` too, the pin predates it); busybox_diff.sh has `--shared-runtime`.

## Not done

- A2: the Pascal runtime (builtinheap, platform, pxxcio) is still compiled into
  every object; it is merged by B instead. That is the remaining ~2.3 s per unit.
- aarch64: the code path exists (runtime built without --function-sections)
  but no aarch64 link was tested.
- Runtime cache is never pruned; old compiler hashes accumulate (~1 MB each).

Test: test/c_shared_runtime_{main,part}.c (Makefile rows c_srt, c_srt_d, c_srt_dg).

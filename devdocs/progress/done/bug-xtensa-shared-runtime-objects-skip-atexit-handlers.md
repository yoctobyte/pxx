---
track: ESP
tags: [xtensa, shared-runtime, atexit, crtl, gibux, busybox]
prio: 5
type: bug
blocked-by: []
summary: "A windowed xtensa program built --shared-runtime and linked with a runtime object never ran its atexit handlers when main returned. atexit() resolved to rt.o, so the handler went into rt.o's table, but the object's entry stub called its OWN finalizer runner, which drained a private, empty copy of that table. The stub now ends with rt.o's exit(main's result) (C11 5.1.2.2.3: returning from main is exit). Found by pxx on Gibux with test/c_xtensa_posix_main.c."
status: done
owner: unassigned
---

# --shared-runtime objects skipped atexit handlers

Repro (pxx, latest-4ac76236c1): test/c_xtensa_posix_main.c built --shared-runtime and linked with rt.o (`#include <pxx/runtime_all.h>` built without the flag). It printed the argc line and exited 3, but "atexit ran" never appeared. The self-contained build printed it. PIE and fixed-address links behaved the same, so the loader was not involved.

## Cause
In the object, `atexit` was UND (imported from rt.o), while `__pxx_run_finalizers` → `__fini_pxxcio` → `__pxx_atexit_run` were local copies that read the object's own gAtExitCount.

## Fix
cparser.inc, the windowed posix entry stub: under SharedRuntime, main's result is already in a10 and the stub calls an external `exit` (UND, resolved to rt.o). rt.o's exit runs its own __pxx_atexit_run and then exits with that code. rt.o's only unit finalizer is that same drain (__fini_pxxcio), so nothing is skipped. The non-shared stub is unchanged.

## Test
tools/check_xtensa_posix_main.py now also builds a runtime object plus a --shared-runtime object and links them, and wants the same output and exit 3. The previous compiler fails it.

Follow-up (not done): the object's local __fini_pxxcio is emitted outside any proc body, so DCE treats it as always live. ~700 B of __pxx_atexit_run/PXXNilRef/PXXWriteNL/PXXSysWrite stays in every --shared-runtime object even though nothing calls it now.

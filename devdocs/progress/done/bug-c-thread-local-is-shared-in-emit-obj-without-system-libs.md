---
slug: bug-c-thread-local-is-shared-in-emit-obj-without-system-libs
track: C
prio: 60
type: bug
status: done
created: 2026-11-21
found-by: rainyday (all-pxx rumpnic boot)
tags: [cfront, tls, threads, rump]
blocked-by: []
summary: "DONE 2026-11-21: in an --emit-obj object built without --system-libs, a C `__thread` was ONE shared variable, crtl's `static __thread` pthread key table with it, so pthread_getspecific was process-wide. The all-pxx rumpnic died at boot on `pthread_getspecific(curlwpkey) == NULL` (rumpuser_pth.c:731). The ELF-TLS path was gated on --system-libs because pxx --link once had no TLS; it has since feature-a-pxx-link-has-no-elf-tls, so the gate is gone. Test c_ltlo / c_ltlo_g."
---

# `__thread` is shared in an --emit-obj object without --system-libs

## Report (rainyday, 2026-11-21)

The all-pxx rumpnic links (458 rump objects plus librumpuser, all
`--threadsafe`, pxx c96c6c0f94) and dies at boot:

    assertion failed: pthread_getspecific(curlwpkey) == NULL (librumpuser/rumpuser_pth.c:731)

Reduced: `static __thread int v = 5;`, main sets 11, a thread reads it.
pxx `--emit-obj --threadsafe` plus `--link --threadsafe`: the thread sees 11,
both threads have the same `&v`, and main ends with the thread's 22. gcc gives
5, different addresses, 11. pthread keys did the same, because crtl keeps
them in `static __thread void *pxx_key_val[]` (lib/crtl/src/pthread.c).

## Cause

`CApplyThreadLocalStorage` (cparser.inc) gave an x86-64 object real ELF TLS (its own
`.tdata.<name>`) only under `--system-libs`. That condition was written while
pxx's own `--link` had no PT_TLS and no TPOFF/GOTTPOFF resolution. Every other
object fell through to pxx's thread-block storage, which an object cannot use
(nothing installs a block), so the variable degraded to one shared copy.

`pxx --link` has had ELF TLS since feature-a-pxx-link-has-no-elf-tls: PT_TLS,
the main thread's block from the entry stub, each pthread's from crtl. So the
condition was simply out of date.

## Fix

The `--system-libs` requirement is dropped. The other conditions stay: x86-64,
a program object (not `--shared`), and an initialiser only where it can be
baked into `.tdata`.

## Test

`test/c_link_thread_local_objects.c`, rows `c_ltlo` (pxx --link) and
`c_ltlo_g` (gcc links the same object). Three threads each see the initial
value 5, a NULL key, and their own counter, and main keeps its own. The
expected output is gcc's. A direct build gives the same.

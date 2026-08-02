/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CPYEXT_PYTHREAD_H
#define PXX_CPYEXT_PYTHREAD_H 1

/* pxx's stand-in for CPython's <pythread.h>.
 *
 * Generated extension code (Cython above all) `#include`s this by name from
 * its atomics preamble, unconditionally, before any feature test — so the file
 * has to EXIST or the translation unit dies at the include, long before
 * anything interesting is measured.
 *
 * DELIBERATELY EMPTY of the thread API. This runtime is single-interpreter and
 * exposes no GIL (see the cpyext ticket's out-of-scope list: GIL APIs,
 * PyThread_* locks, thread-local storage). Nothing here declares
 * PyThread_allocate_lock / acquire / release / PyThread_tss_*: an extension
 * that genuinely needs them must fail at COMPILE with the name it wanted,
 * not link against a lock that does nothing.
 *
 * Cython's own use of this header is the atomics block guarding refcount
 * fast paths; with no threads, its non-atomic fallback is the correct
 * lowering and is what gets compiled. */

#endif /* PXX_CPYEXT_PYTHREAD_H */
